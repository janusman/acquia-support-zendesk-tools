#!/opt/lampp/bin/php
<?php

require '../zendesk_api.php.inc';
require 'ZendeskTicketProcessor.php';

if (empty($argv[1])) {
  echo "Usage: " . $argv[0] . " [zendesk-ticket-number]\n";
  exit;
}

$tickets = [ zendesk_get_ticket($argv[1]) ];

foreach ($tickets as $ticket) {
  print_r($ticket);
  echo "Processing ticket " . $ticket->id . "\n";
  $runner = new ZendeskTicketProcessorAhtpanicrunner($ticket);
  $runner->execute();
}
