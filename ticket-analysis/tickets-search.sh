#!/bin/bash

date=`php -r '$days = 90; echo gmdate("Y-m-d\TH:00:00\Z", time() - (3600 * 24 * $days));'`

if [ "${1:-x}" = x ]
then
  echo "Usage: $0 [search string]"
  echo 
  echo "Examples"
  cat <<EOF
  $0 outage
  $0 stampede
  $0 "PDOException created>=2017-11-01"
  $0 tags:rc:search
  $0 tags:p:content_hub
  $0 tags:rcs:dos_ddos_attack
  $0 "type:ticket created>$date -tags:ticket:submitted_ops -tags:ticket:proactive"
EOF
  exit 0
fi

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmpout=/tmp/output.json
CREDS_FILE=$BASE_DIR/creds.txt

if [ ! -r $CREDS_FILE ]
then
  echo "Place a one-liner into a creds.txt file, with this information:"
  echo ""
  echo "YourEmail@acquia.com:PassWordUsedToLogIntoZendesk"
  echo ""
  echo "Or, a ZD API token string:"
  echo ""
  echo "YourEmail@acquia.com/token:TokenString"
  exit 0
fi

# Test run
credentials=`cat $CREDS_FILE`

curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=${1}" >ticket-export.json

# Count
#cat ticket-export.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); echo "Number of tickets: " . count($result->results) . "\n";'

#cat ticket-export.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { echo $ticket->id . "\t" . $ticket->subject . "\n"; }'

# Process results
php -r '
require_once "../auto-ahtpanic-on-tickets/SupportSuggesterMatchingService.php";

$suggestion_statuses = ["released", "review", "suggestion"];
$cache_enabled = false;
$matcher_service = new SupportSuggesterMatcherService($suggestion_statuses, $cache_enabled);
 
$result = json_decode(file_get_contents("ticket-export.json")); 
echo "Number of tickets: " . count($result->results) . "\n";
$counts = [ "match" => 0, "no_match" => 0];
foreach ($result->results as $ticket) {
  $subject = $ticket->subject ?? "";
  $description = $ticket->description ?? "";
  echo "[ " . $ticket->id . " ]: " . $subject . "\n";
  echo "          ... " . substr(preg_replace(["/[\n\r]/", "/  */"], " ", $description), 0, 100) . "...\n";
  echo "          https://acquia.zendesk.com/agent/tickets/" . $ticket->id . "\n";
  $string = "$subject $description";
  $matches = $matcher_service->getMatches($string);
  if ($matches) {
    echo "MATCH: ";
    print_r($matches);
    echo "\n";
    $counts["match"]++;
  }
  else {
    #echo "NO MATCH: Ticket #" . $ticket->id . " - " . $subject . "\n";
    #echo "          ... " . substr($description, 0, 80) . "...\n";  
    $counts["no_match"]++;
  }
}
echo "\nSummary --------\n";
print_r($counts);'

exit
#########################
#########################  THE END  #######################
#########################

# From ticket-export.json
stdClass Object
(
    [tickets] => Array
        (
            [0] => stdClass Object
                (
                    [url] => https://acquia.zendesk.com/api/v2/tickets/268654.json
                    [id] => 268654
{ ... snip ... }
                    [created_at] => 2016-03-24T20:01:12Z
                    [updated_at] => 2016-03-30T21:23:49Z
                    [type] => question
                    [subject] => Apache Solr for Dev and Staging environments
                    [raw_subject] => Apache Solr for Dev and Staging environments
                    [description] => We are using Apache Solr on our site and I noticed that there is only 1 Apache S
 
# ...and the fields with the root cause


#curl -su $credentials https://acquia.zendesk.com/api/v2/tickets/$ticket.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); print_r($result);'



# Tasks to actually get a dump of ticket comments per root cause.
# 
# 



