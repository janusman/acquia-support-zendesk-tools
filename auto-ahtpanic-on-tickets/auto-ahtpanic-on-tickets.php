<?php

require '../zendesk_api.php.inc';
require 'ZendeskTicketProcessor.php';

function search_tickets() {
  // $query = "status<=open type:ticket is_public:1 priority:urgent created>2017-05-01";

  // Set time to UTC and get date.
  date_default_timezone_set("UTC");
  $since_date = date('Y-m-d\TH:00:00\Z', time() - (3600 * 5));
  // Only recent tickets...
  $query = " created>=$since_date";
  // Ticket types we want...
  $query .= " status<=open type:ticket priority>=high";
  #$query .= " (subject:down OR subject:\"service interruption\")";
  // Omit tickets where we've already touched.
  $query .= " -@xvr10000";
  echo "Getting tickets with query:\n  $query\n";
  $tickets = zendesk_search_tickets($query);
  if (isset($tickets->error)) {
    echo "ERROR: Zendesk search failed with error.\n";
    #print_r($tickets);
    die();
  }
  echo "Found " . count($tickets->results) . " tickets.\n";
  return $tickets->results;
}

$tickets = search_tickets();
foreach ($tickets as $ticket) {
  $runner = new ZendeskTicketProcessorAhtpanicrunner($ticket);
  $runner->execute();
}
