<?php
/**
 * Class to process ZD tickets.
 */

abstract class ZendeskTicketProcessor {
  protected $ticket;
  protected $action_queue = array();
  protected $action_types = ['postCommentAndFile', 'postComment'];
  protected $storage = array();

  function __construct($ticket) {
    $this->ticket = $ticket;
  }

  function log($msg) {
    echo '[ZD ' . $this->ticket->id . ']';
    echo ' \\' . get_class($this) . ":";
    echo debug_backtrace()[1]['function'] . "() -> $msg\n";
  }

  function queueAction($action) {
    if (!isset($action['type'])) {
      die("ERROR: queueAction(): Missing action type");
    }
    if (!in_array($action['type'], $this->action_types)) {
      die("ERROR: Wrong ticket action type " . $action['type']);
    }
    $this->action_queue[] = $action;
    $this->log("Queued the action " . $action['type']);
  }

  function runActionQueue() {
    foreach ($this->action_queue as $action) {
      $this->runAction($action);
    }
  }

  function runAction($action) {
    switch ($action['type']) {
      case "postCommentAndFile":
        $this->log("Running queued action " . $action['type']);
        zendesk_post_comment_and_file(
          $this->ticket->id,
          $action['args']['comment_body'],
          $action['args']['infile'],
          $action['args']['is_public']
        );
        break;
      case "postComment":
        $this->log("Running queued action " . $action['type']);
        zendesk_post_comment(
          $this->ticket->id,
          $action['args']['comment_body'],
          isset($action['args']['is_public']) ? $action['args']['is_public'] : false
        );
        break;
    }
  }

  function ticketMeetsRequirements() {
    if (empty($this->ticket->id)) {
      return false;
    }
    return true;
  }

  function processTicket() {
    return true;
  }

  function execute() {
    // Check if this ticket meets the filters.
    if (!$this->ticketMeetsRequirements()) {
      return;
    }
    // Process the ticket
    $this->processTicket();

    // Run queue of resulting actions.
    $this->runActionQueue();
  }
}

class ZendeskTicketProcessorAhtpanicrunner extends ZendeskTicketProcessor {
  // Try to extract URLs from a textfield.
  function parseUrls($text) {
    $urls = array();
    foreach (preg_split("/[\s,]+/", trim($text)) as $line) {
      $line = trim($line);
      if (parse_url($line) !== FALSE) {
        // Extract host from each URL.
        $parsed = parse_url($line);
        $urls[] = strtolower($parsed['scheme']) . '://' . strtolower($parsed['host']);
      }
      return $urls;
    }
  }

  function ticketMeetsRequirements() {
    // Get the example URLs field from ticket. (Which is a free Textfield)
    $example_urls = zendesk_get_custom_field($this->ticket, 23786337);
    if ($example_urls && isset($example_urls->value)) {
      // Extract URLs from text.
      $urls = $this->parseUrls($example_urls->value);
      // If no applicable host found, don't run.
      if ($urls) {
        // Store the hostname to trigger on.
        $this->storage['url'] = $urls[0];
        if (count($urls)>1) {
          $this->log("More than one example URL found, using first one only.");
        }
      }
    }
    // TODO: Try just going to @site.env using the UUID from the ticket
    // aht cci request aht/subscription/f80432f4-d731-7444-f99b-42d36c443306/info |grep docroot
    // ==> docroot: tribune1
    if (empty($this->storage['url'])) {
      $this->log("No example URL found in ticket");

      // Attempt fallback
      if ($this->ticket->subject == "Service Interruption Detected on your Production Environment") {
        $docroot = $this->getSitenameFromSubscription();
        if ($docroot) {
          $this->storage['url'] = '@' . $docroot . '.prod';
          return parent::ticketMeetsRequirements();
        }
      }
      #print_r($this->ticket);
      return FALSE;
    }
    // Make sure this URL belongs to an Acquia site
    $doesnt_exist = exec('aht find:domain ' . $this->storage['url'] .' --no-ansi |grep -c "not found"');
    if ($doesnt_exist == "1") {
      $this->log("No acquia site found associated to URL " . $this->storage['url']);
      return FALSE;
    }

    return parent::ticketMeetsRequirements();
  }

  function getSitenameFromSubscription() {
    $uuid = zendesk_get_custom_field($this->ticket, 23786347);
    if (!empty($uuid->value)) {
      exec(
        "aht cci request aht/subscription/{$uuid->value}/info --format=json",
        $output,
        $return_var
      );
      if ($json = json_decode(implode('', $output))) {
        return $json->docroot;
      }
    }
    return false;
  }

  function runCommandWithTimeout($cmd, $timeout) {
    if (!is_numeric($timeout)) {
      die("ERROR: timeout needs to be a number");
    }
    $real_cmd = "timeout {$timeout} $cmd";
    $this->log("Running command $real_cmd");
    $start_time = time();
    exec($cmd, $result_output, $result_code);
    $elapsed_time = time() - $start_time;
    $this->log("Command finished. Took $elapsed_time seconds");

    return [
      'result_output' => implode("\n", $result_output),
      'result_code' => $result_code,
      'elapsed_time' => $elapsed_time,
      'timed_out' => ($result_code == "124"),
    ];
  }

  function processTicket() {
    // Run on the hostname.
    $this->log("Starting processTicket() using " . $this->storage['url']);
    $output_basename = "/mnt/tmp/" . get_class($this) . "-ticket-" . $this->ticket->id;

    if (file_exists("{$output_basename}.html")) {
      $this->log("File {$output_basename}.html already exists. Skipping attaching this to ticket.");
      return false;
    }

    if (!file_exists("{$output_basename}.txt")) {
      $cmd = "/home/alejandrogarza/Dev/Support-Tools/bin/ahtpanic.sh";
      $cmd .= " " . $this->storage['url'] . " 2>&1 >{$output_basename}.txt";

      // Execute with a timeout of 300.
      $command_result = $this->runCommandWithTimeout($cmd, 30);

      if ($command_result['timed_out']) {
        $this->log("Command timed out!");
        return FALSE;
      }
    }

    if (exec("egrep -c 'RuntimeException|InvalidArgumentException' {$output_basename}.txt") != '0') {
      $this->log("Output of the command has Exception messages. Aborting!");
      return FALSE;
    }

    if (exec("fgrep -c '^C' {$output_basename}.txt") != '0') {
      $this->log("Output of the command had ^C (breaks). Aborting!");
      return FALSE;
    }

    // Convert to HTML, with intermediate file for debugging.
    exec("cat {$output_basename}.txt |ansi2html --bg=dark --palette=tango >{$output_basename}.html");

    if (!file_exists("{$output_basename}.html")) {
      $this->log("Could not run ansi2html. Aborting!");
      return FALSE;
    }

    $comment = 'Attaching a run of command `ahtpanic.sh ' . $this->storage['url'] . '`.';
    $comment .= ' (Took ' . $command_result['elapsed_time'] . " secs).\n";
    $comment .= "\n";
    $comment .= "[Leave feedback here!](https://docs.google.com/spreadsheets/d/1v-jVOmpt_gP9MJ2cl3dxhfG7tCcumV4Tgc5FCnn1AO4/edit#gid=0).\n";
    $comment .= "*\"I panic so you don't have to!\" @xvr10000*";
    $action = [
      'type' => "postCommentAndFile",
      'args' => [
        'comment_body' => $comment,
        'infile' => "{$output_basename}.html",
        'is_public' => 0,
      ],
    ];
    $this->queueAction($action);

  }
}
