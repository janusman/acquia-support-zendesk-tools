#!/usr/bin/env php
<?php

/**
 * Command-line tool to process a single ticket.
 */
require __DIR__ . '/../zendesk_api.php.inc';
require __DIR__ . '/ZendeskTicketProcessor.php';

if (empty($argv[1])) {
  echo "Runs the ZendeskTicketProcessorAhtpanicrunner class on one ZD ticket.\n";
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
