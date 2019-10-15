#!/bin/bash

COLOR_RED=$(tput setaf 1) #"\[\033[0;31m\]"
COLOR_YELLOW=$(tput setaf 3) #"\[\033[0;33m\]"
COLOR_GREEN=$(tput setaf 2) #"\[\033[0;32m\]"
COLOR_GRAY=$(tput setaf 7) #"\[\033[2;37m\]"
COLOR_NONE=$(tput sgr0) #"\[\033[0m\]"
MODE=all
RULE_ID=0

# Get options
# http://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options/7680682#7680682
while test $# -gt 0
do
  case $1 in

  # Normal option processing
    -h | --help)
      HELP=1
      ;;
    -y)
      YES="-y"
      ;;
  # Special cases
    --)
      break
      ;;
  # Long options
    --help)
      HELP=1
      ;;
    --only-match-rule=*)
      RULE_ID=`echo $1 |cut -f2 -d=`
      MODE=only
      echo "Only showing tickets that MATCH rule $RULE_ID"      
      ;;
    --dont-match-rule=*)
      RULE_ID=`echo $1 |cut -f2 -d=`
      MODE=exclude
      echo "Only showing tickets that DO NOT match rule $RULE_ID"
      ;;
    --*)
      # error unknown (long) option $1
      echo "  ${COLOR_RED}Warning: Unknown option $1${COLOR_NONE}"
      ;;
    -?)
      # error unknown (short) option $1
      ;;

  # MORE FUN STUFF HERE:
  # Split apart combined short options
  #  -*)
  #    split=$1
  #    shift
  #    set -- $(echo "$split" | cut -c 2- | sed 's/./-& /g') "$@"
  #    continue
  #    ;;

  # Done with options, the sitename comes last.
    *)
      SEARCH=$1
      ;;
  esac

  shift
done

date=`php -r '$days = 90; echo gmdate("Y-m-d\TH:00:00\Z", time() - (3600 * 24 * $days));'`
#SEARCH="created>$date"

if [ "${SEARCH:-x}" = x ]
then
  HELP=1
fi

if [ ${HELP:-x} = 1 ]
then
  cat <<EOF
USAGE: $0 [--only-match-rule|--dont-match-rule] [search string]

Clones a site locally. Usage:
  $0 [options] "Zendesk search string"
Options:
  -h or --help            : Shows this help text and exits.
  --only-match-rule=[num] : Only shows tickets that match a certain Rule
  --dont-match-rule=[num] : Only shows tickets that DO NOT match a certain Rule
  
Examples:
  $0 outage
  $0 --dont-match-rule=55 outage
  $0 "PDOException created>=2017-11-01"
  $0 tags:rc:search
  $0 tags:p:content_hub
  $0 tags:rcs:dos_ddos_attack
  $0 "type:ticket created>$date -tags:ticket:submitted_ops -tags:ticket:proactive"

EOF
  exit
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

echo "Searching for: $SEARCH"
echo curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=$SEARCH"
curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=$SEARCH" >ticket-export.json

## Extract just id/subject/description from tickets
php -r '
$tickets = [];
$result = json_decode(file_get_contents("ticket-export.json"));
if (!empty($result->results)) {
  $tickets = $result->results;
}
foreach ($tickets as $ticket) {
  echo "https://acquia.zendesk.com/agent/tickets/" . $ticket->id ."\n*** " . $ticket->subject . "\n    " . preg_replace("/[\n\r]/", " ", substr($ticket->description,0,1024)) . "\n\n---------------------\n";
}
' > ticket-export-simplified.txt

echo "Simplified output is in ticket-export-simplified.txt:"
ls -l ticket-export-simplified.txt
echo "=================================================="
echo ""

# Process results
php -r '
$rule_id = intval('$RULE_ID');
$rule_mode = "'$MODE'";
require_once "../auto-ahtpanic-on-tickets/SupportSuggesterMatchingService.php";

$suggestion_statuses = ["released", "review", "suggestion"];
$cache_enabled = false;
$matcher_service = new SupportSuggesterMatcherService($suggestion_statuses, $cache_enabled);
 
function rule_any_match($matches) {
  return count($matches) > 0;
}

function rule_id_match($matches, $rule_id) {
  foreach ($matches as $match) {
    if ($match["row_num"] == $rule_id) {
      return true;
    }
  }
  return false;
}
 
$result = json_decode(file_get_contents("ticket-export.json")); 
echo "Number of tickets: " . count($result->results) . "\n";
$counts = [ "match" => 0, "no_match" => 0];
foreach ($result->results as $ticket) {
  $subject = $ticket->subject ?? "";
  $description = $ticket->description ?? "";
  $string = "$subject $description";
  $matches = $matcher_service->getMatches($string);

  if ($rule_mode == "only" && !rule_id_match($matches, $rule_id)) {
    continue;
  }
  
  if ($rule_mode == "exclude" && rule_id_match($matches, $rule_id)) {
    continue;
  }
    
  echo "[ " . $ticket->id . " ]: " . $subject . "\n";
  echo "          ... " . substr(preg_replace(["/[\n\r]/", "/  */"], " ", $description), 0, 100) . "...\n";
  echo "          https://acquia.zendesk.com/agent/tickets/" . $ticket->id . "\n";

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



