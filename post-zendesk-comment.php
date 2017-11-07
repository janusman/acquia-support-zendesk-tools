<?php

require 'zendesk_api.php.inc';

##############################
# MAIN

if (!isset($argv[1]) || !isset($argv[2]) || !isset($argv[3]) || !isset($argv[4])) {
  echo "Usage: " . $argv[0] . " ticketNumber commentFile attachmentFile [public|private]\n";
  exit();
}
$ticket_number = $argv[1];
$comment_file = $argv[2];
$attachment_file = $argv[3];
$is_public = ($argv[4] == 'public');
if (! is_numeric($ticket_number)) {
  die("First argument should be a number.\n");
}
if (! $comment_body = @file_get_contents($comment_file)) {
  die("Can't read file $comment_file\n");
}
if (! is_file($attachment_file)) {
  die("Can't read file $attachment_file\n");
}
zendesk_post_comment_and_file($ticket_number, $comment_body, $attachment_file, $is_public);
