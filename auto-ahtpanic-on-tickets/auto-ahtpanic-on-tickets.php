<?php

// This script queries the ticket queue once, determines tickets to put comments in
// and adds them.

define('HOURS_BACK', 72);

require '../zendesk_api.php.inc';
require 'ZendeskTicketProcessor.php';
require 'SupportSuggesterMatchingService.php';

function output_color($color, $msg) {
  $colors = [
    'green' => "\e[1;32;40m",
    'blue' => "\e[0;34;40m",
    'bluebackground' => "\e[0;30;44m",
    'yellow' => "\e[1;33;40m",
    'none' => "\e[0m"
  ];
  if (isset($colors[$color])) {
    echo $colors[$color] . $msg . $colors['none'] . PHP_EOL;
  }
  else {
    echo $msg . PHP_EOL;
  }
}

function get_zd_tickets_using_query($query) {
  output_color("green","Getting tickets with query:\n  $query");
  $tickets = zendesk_search_tickets($query);
  if (isset($tickets->error)) {
    output_color("red", "ERROR: Zendesk search failed with error.");
    die();
  }
  echo "Found " . count($tickets->results) . " tickets.\n";
  return $tickets->results;
}

function attempt_ticket_match_against_support_ticket_suggester($matcher_service, $ticket) {
  $ticket_text = $ticket->subject . "\n" . $ticket->description;
  $matches = $matcher_service->getMatches($ticket_text);
  if (count($matches) > 0) {
    echo "              Support ticket autocomplete matches found:\n";
    foreach ($matches as $match) {
      echo "               * " . $match['title'] . "\n";
      echo "                 " . $match['url'] . "\n";
    }
  }
}

/** Unused...
function has_ticket_been_processed($ticket_id, $set_processed = false) {
  static $ticket_processed_cache = [];
  $max_items = 50;
  $filename = "/mnt/tmp/ticket-processed-cache.json";

  if ($ticket_processed_cache == false) {
    @$ticket_processed_cache = unserialize(file_get_contents($filename));
  }
  if (!is_array($ticket_processed_cache)) {
    $ticket_processed_cache = [];
  }

  if ($set_processed) {
    $ticket_processed_cache[$ticket_id] = true;
  }
  $result = isset($ticket_processed_cache[$ticket_id]);

  // Make the array act like an LRU cache with a max size of $max_items
  while (count($ticket_processed_cache)>=$max_items) {
    // Remove the first item off the array.
    reset($ticket_processed_cache); unset($ticket_processed_cache[key($ticket_processed_cache)]);
  }

  // Store results
  file_put_contents($filename, serialize($ticket_processed_cache));

  return $result;
}
**/

function run_process_on_matching_tickets($query) {
  // Get tickets
  $tickets = get_zd_tickets_using_query($query);

  // Instantiate the matcher service
  $matcher_service = new SupportSuggesterMatcherService();

  // Process each ticket.
  foreach ($tickets as $ticket) {
    // Skip tickets that have already been processed.
    #if (has_ticket_been_processed($ticket->id)) {
    #  continue;
    #}

    output_color("yellow","[ZD {$ticket->id}] : Processing ticket: \"" . substr($ticket->subject, 0, 80) . "\"");
    output_color("yellow", "               https://acquia.zendesk.com/agent/tickets/{$ticket->id}");

    // Run the matching service.
    attempt_ticket_match_against_support_ticket_suggester($matcher_service, $ticket);

    // Run the ticket processor.
    $runner = new ZendeskTicketProcessorAhtpanicrunner($ticket);
    $runner->execute();
    echo "\n";

    #has_ticket_been_processed($ticket->id, true);
  }
}

function main() {

  // Run on ZD queries for incoming ticket queue. Define groups in our ticket search
  $groups = [ 'group_id:52560', 'group:"SE-*"' ];
  foreach ($groups as $group) {

    // Build the query.
    // Only recent tickets...
    $query = ' created>=' . gmdate('Y-m-d\TH:00:00\Z', time() - (3600 * HOURS_BACK));
    // Ticket types we want...
    $query .= ' status<solved type:ticket priority>=normal -gc:fs -tags:notification -tags:bulk_created -tags:waiting:ops_maint -tags:p:mautic -tags:p:agilone -tags:agilone -tags:agilone_legacy_user';
    // Queue we want...
    $query .= " " . $group;
    // Omit tickets that we've already touched.
    $query .= ' -@xvr10000';

    run_process_on_matching_tickets($query);
  }

  // Run on manual invocations that mention $magic_words, but created <$days ago.
  $magic_words = [ '@makeitso OR @alejandrobot', '+tags:assist_req'];
  $days = 15;
  foreach ($magic_words as $magic_word) {
    $query = $magic_word . ' status<=closed -@xvr10000 created>=' . gmdate('Y-m-d\TH:00:00\Z', time() - (3600 * 24 * $days));
    run_process_on_matching_tickets($query);
  }
}

main();
