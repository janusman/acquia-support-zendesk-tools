<?php

// This should end in /api/v2 (NO trailing slash!)
define("ZD_URL", "https://acquia.zendesk.com/api/v2");
define("ZD_CREDS_FILE", __DIR__ . "/creds.txt");
define("ZD_USERAGENT", "AcquiaAlejandroGarza/1.0");

function zendesk_curl($url, $json, $action)
{
  if (substr($url, 0, 1) != "/") {
    die("Wrong URL given: $url");
  }
  $creds = trim(file_get_contents(ZD_CREDS_FILE));
  $ch = curl_init();
  curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
  curl_setopt($ch, CURLOPT_MAXREDIRS, 10 );
  curl_setopt($ch, CURLOPT_URL, ZD_URL . $url);
  curl_setopt($ch, CURLOPT_USERPWD, $creds);
  switch($action) {
    case "POST":
      curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "POST");
      curl_setopt($ch, CURLOPT_POSTFIELDS, $json);
      break;
    case "GET":
      curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "GET");
      break;
    case "PUT":
      curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
      curl_setopt($ch, CURLOPT_POSTFIELDS, $json);
      break;
    case "DELETE":
      curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "DELETE");
      break;
    default:
      break;
  }
  curl_setopt($ch, CURLOPT_HTTPHEADER, array("Content-type: application/json"));
  curl_setopt($ch, CURLOPT_USERAGENT, ZD_USERAGENT);
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
  curl_setopt($ch, CURLOPT_TIMEOUT, 10);
  $output = curl_exec($ch);
  curl_close($ch);
  $decoded = json_decode($output);
  return $decoded;
}

function zendesk_get_ticket($ticket_id) {
  if (!is_numeric($ticket_id)) {
    die("ERROR: No ticket number given");
  }
  $url = "/tickets/" . intval($ticket_id) . ".json";
  $result = zendesk_curl($url, null, "GET");
  return $result->ticket;
}

function zendesk_search_tickets($search_string) {
  #curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=type:ticket created>2016-01-01 -tags:ticket:submitted_ops -tags:ticket:proactive ${1}" >ticket-export.json
  if (!$search_string) {
    die("ERROR: Missing search_string argument.");
  }
  $url = "/search.json?query=" . urlencode($search_string);
  $result = zendesk_curl($url, null, "GET");
  return $result;
}

# Post a comment
function zendesk_post_comment(
  $ticket_number,
  $comment_body,
  $is_public = false,
  $uploads_token = null,
  $ticket_status = null
) {
  if (!$comment_body) {
    die("ERROR: Missing content_body argument.");
  }
  if (!is_numeric($ticket_number)) {
    die("ERROR: Ticket should be a number, got '$ticket_number'");
  }
  $ticket_object = array(
    'ticket' => array(
      'comment' => array(
        'public' => $is_public,
        'body' => $comment_body,
        'uploads' => $uploads_token,
      )
    )
  );
  if ($ticket_status) {
    $ticket_object['status'] = $ticket_status;
  }
  $json = json_encode($ticket_object);
  $url = "/tickets/{$ticket_number}.json";
  $result = zendesk_curl($url, $json, "PUT");
  return $result;
}

# Use $uploads_token from previous upload's $result->upload->token if needed.
function zendesk_post_file($source_file, $human_short_filename, $uploads_token=null) {
  $url = ZD_URL . "/uploads.json?filename=$human_short_filename";
  if ($uploads_token) {
    $url .= '&token=' . $uploads_token;
  }
  if (!file_exists($source_file)) {
    die("ERROR: File $source_file does not exist!");
  }
  $file_descriptor = fopen($source_file, "r");
  $size = filesize($source_file);
  $creds = trim(file_get_contents(ZD_CREDS_FILE));
  $ch = curl_init($url);
  curl_setopt($ch, CURLOPT_USERPWD, $creds);
  curl_setopt($ch, CURLOPT_URL, $url);
  curl_setopt($ch, CURLOPT_POST ,1);
  curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-type: application/binary'));
  curl_setopt($ch, CURLOPT_POSTFIELDS, fread($file_descriptor, $size));
  curl_setopt($ch, CURLOPT_POST ,1);
  curl_setopt($ch, CURLOPT_INFILE, $file_descriptor);
  curl_setopt($ch, CURLOPT_INFILESIZE, $size);
  curl_setopt($ch, CURLOPT_FOLLOWLOCATION ,1);
  curl_setopt($ch, CURLOPT_HEADER ,0); // DO NOT RETURN HTTP HEADERS
  curl_setopt($ch, CURLOPT_USERAGENT, ZD_USERAGENT);
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
  curl_setopt($ch, CURLOPT_TIMEOUT, 10);
  $output = curl_exec($ch);
  $error = curl_error($ch);
  $http_code = curl_getinfo($ch ,CURLINFO_HTTP_CODE);
  curl_close($ch);
  $decoded = json_decode($output);
  return $decoded;
}

function zendesk_post_comment_and_file($ticket_number, $comment_body, $infile, $is_public = false) {
  echo "Trying to upload file $infile into ticket...\n";
  $human_short_filename = basename($infile);
  $result = zendesk_post_file($infile, $human_short_filename);
  if (isset($result->upload)) {
    # Upload was successful!
    echo "Upload successful!\n";
    echo "Adding comment to ticket...\n";
    $uploads_token = $result->upload->token;
    zendesk_post_comment($ticket_number, $comment_body, $is_public, $uploads_token);
    echo "Comment added!\n";
  }
}

function zendesk_get_custom_field($ticket, $field_id) {
  if (empty($ticket->custom_fields)) {
    return false;
  }
  if (!is_array($ticket->custom_fields)) {
    return false;
  }
  foreach ($ticket->custom_fields as $field) {
    if ($field->id == $field_id) {
      return $field;
    }
  }
  return false;
}
