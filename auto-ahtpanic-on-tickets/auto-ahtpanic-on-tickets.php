<?php

// This script queries the ticket queue once, determines tickets to put comments in
// and adds them.

define('HOURS_BACK', 1);

require '../zendesk_api.php.inc';
require 'ZendeskTicketProcessor.php';

function get_zd_tickets_using_query($query) {
  echo "Getting tickets with query:\n  $query\n";
  $tickets = zendesk_search_tickets($query);
  if (isset($tickets->error)) {
    echo "ERROR: Zendesk search failed with error.\n";
    die();
  }
  echo "Found " . count($tickets->results) . " tickets.\n";
  return $tickets->results;
}

// Build the query.
// Only recent tickets...
$query = ' created>=' . gmdate('Y-m-d\TH:00:00\Z', time() - (3600 * HOURS_BACK));
// Ticket types we want...
$query .= ' status<=open type:ticket priority>=normal group:"Acquia network support"';
// Omit tickets that we've already touched.
$query .= ' -@xvr10000';

// Get tickets
$tickets = get_zd_tickets_using_query($query);

// Process each ticket.
foreach ($tickets as $ticket) {
  $runner = new ZendeskTicketProcessorAhtpanicrunner($ticket);
  $runner->execute();
}
