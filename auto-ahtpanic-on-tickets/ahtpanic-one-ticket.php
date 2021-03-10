#!/usr/bin/env php
<?php

/**
 * Command-line tool to process a single ticket.
 */
require __DIR__ . '/../zendesk_api.php.inc';
require __DIR__ . '/ZendeskTicketProcessor.php';
require __DIR__ . '/SupportSuggesterMatchingService.php';

function attempt_ticket_match_against_support_ticket_suggester($matcher_service, $ticket) {
  $ticket_text = $ticket->subject . "\n" . $ticket->description;
  $matches = $matcher_service->getMatches($ticket_text);
  if (count($matches) > 0) {
    echo "              Support ticket autocomplete matches found:\n";
    foreach ($matches as $match) {
      echo "               * " . $match['title'] . " [status->" . $match['status'] ."]\n";
      echo "                 " . $match['url'] . "\n";
    }
  } else {
    echo "              No Support ticket autocomplete matches found.\n";
  }
}

if (empty($argv[1])) {
  echo "Runs the ZendeskTicketProcessorAhtpanicrunner class on one ZD ticket.\n";
  echo "Usage: " . $argv[0] . " [zendesk-ticket-number]\n";
  exit(1);
}

$id = $argv[1];
$ticket = @zendesk_get_ticket($argv[1]);
if (empty($ticket)) {
  echo "Could not get ticket ID $id\n";
  exit(1);
}
$tickets = [ $ticket ];

// Instantiate the matcher service
$matcher_service = new SupportSuggesterMatcherService(['released', 'review', 'suggestion'], false);

foreach ($tickets as $ticket) {
  print_r($ticket);

  echo "[ZD {$ticket->id}] : Processing ticket: \"" . substr($ticket->subject, 0, 80) . "\"\n";
  echo "              https://acquia.zendesk.com/agent/tickets/{$ticket->id}\n";

  // Run the matching service.
  attempt_ticket_match_against_support_ticket_suggester($matcher_service, $ticket);

  $runner = new ZendeskTicketProcessorAhtpanicrunner($ticket);
  // Set destination of files.
  $date = gmdate("Ymd-Hi") . "UTC";
  $runner->setOutputBasename("/mnt/tmp/AutoPanic-on-demand-{$date}-ticket-" . $ticket->id);
  // Remove any previous files.
  $runner->removeOutputFiles();
  $runner->execute();
}
