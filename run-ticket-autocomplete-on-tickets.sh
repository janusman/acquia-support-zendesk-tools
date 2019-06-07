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
  $0 tags:rcs:dos_ddos_attack
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

# Only recent tickets...
date=`php -r '$days = 90; echo gmdate("Y-m-d\TH:00:00\Z", time() - (3600 * 24 * $days));'`
echo "Getting tickets newer than $date ..."

curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=type:ticket created>$date -tags:ticket:submitted_ops -tags:ticket:proactive (group:\"Acquia network support\" OR group:\"SE-*\") ${1}" >$tmpout

cat $tmpout |php -r '
  include "/home/alejandrogarza/Dev/acquia-support-zendesk-tools/auto-ahtpanic-on-tickets/SupportSuggesterMatchingService.php";
  $x = new SupportSuggesterMatcherService(["released", "review"], false); 
  $result = json_decode(trim(stream_get_contents(STDIN))); 
  foreach ($result->results as $i => $t) { 
    $string = str_replace(["\n", "\r"], "  ", $t->subject . " " . $t->description); 
    $m = $x->getMatches($string); 
    if (!empty($m)) { 
      echo "Ticket: https://acquia.zendesk.com/agent/tickets/{$t->id} =================\n";
      foreach ($m as $num => $match) {
        echo "  Match $num ----\n";
        print_r($match);
        $rule = addslashes($match["match_string"]);
        file_put_contents("/tmp/tmp.txt", $string);
        $cmd = "egrep --color \"$rule\" /tmp/tmp.txt";
        #echo $cmd . "\n";
        system("egrep --color=always -i \"^|$rule\" /tmp/tmp.txt", $status);
      }
    } 
  }'
