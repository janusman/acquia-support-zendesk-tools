#!/bin/bash

if [ "${1:-x}" = x ]
then
  echo "Usage: $0 [search string]"
  echo 
  echo "Examples"
  cat <<EOF
  sh tickets-analysis.sh outage
  sh tickets-analysis.sh stampede
  sh tickets-analysis.sh "PDOException created>=2017-11-01"
  sh tickets-analysis.sh tags:rc:search
  sh tickets-analysis.sh tags:rcs:dos_ddos_attack
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
#curl -su $credentials https://acquia.zendesk.com/api/v2/ticket_fields.json >$tmpout

#if [ `grep -c "Couldn't authenticate you" $tmpout` -eq 1 ]
#then
#  echo "Couldn't authenticate against Zendesk. Make sure $CREDS_FILE has the correct credentials."
#  exit 1
#fi

# Get custom fields
#cat $tmpout >fields.json

# Search by root cause?
#https://developer.zendesk.com/rest_api/docs/core/search

# Or... mass-export tickets, and then use data to build tagcloud
#curl -su $credentials "https://acquia.zendesk.com/api/v2/incremental/tickets.json?start_time="`php -r 'echo time()-(300*24);'` >$tmpout

#curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json?query=tags:rcs:${1}" >$tmpout

# Only recent tickets...
date=`php -r '$days = 90; echo gmdate("Y-m-d\TH:00:00\Z", time() - (3600 * 24 * $days));'`
echo "Getting tickets newer than $date ..."

curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=type:ticket created>$date -tags:ticket:submitted_ops -tags:ticket:proactive (group:\"Acquia network support\" OR group:\"SE-*\") ${1}" >$tmpout

# Count tickets
cat $tmpout |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); echo "Tickets found: " . count($result->results) . PHP_EOL;'

echo "Random sampling of some ticket titles:"
cat $tmpout |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { echo "   #" . $ticket->id ."  " . $ticket->subject . "\n"; }' |sort -R |head -20
echo ""

cat $tmpout |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { echo $ticket->subject . "\n"; echo $ticket->description . "\n"; };' >test.out 

echo "Top lines (URLs, numbers and some paths have been replaced with placeholders):"
cat test.out  |tr 'A-Z' 'a-z' |tr -d '\015' |sed -e 's/request[-_]id="*[a-fv0-9"-]*/{request-id}/g' -e 's%https*://[a-z0-9_./?&=-]*%{url}%g' -e 's%www/html/[a-z][a-z0-9]*/%www/html/{site}/%g' -e 's/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/{time}/g' -e 's/[0-9][0-9\.]*/{num}/g' -e 's/  */ /g' -e 's/^ //g' -e 's/ $//g' -e 's/[a-z][a-z0-9]*@/{user}@/g' -e 's/:[a-z][a-z0-9]*.git/:{name}.git/g' |sed -e '/^$/d' -e '/^[a-z][a-z ]*,$/d' | egrep -v '^(.$|..$|...$|thank|hello|hi)' |sort |uniq -c |sort -nr |head -20

echo "Top mentioned words:"
cat test.out |tr 'A-Z' 'a-z' |sed -e 's/[^a-z0-9A-Z]/ /g' -e 's/  */ /g' -e 's/ /\n/g' |sed -e '/^$/d' |egrep -v '^(.|..|for|the|have|here|there|and|but|was|been|you|she|they|them|this|has|with|without|may|that|those|are|your|mine|our|ours|yours|can|from|will|please|thank|thanks|hello|were|regards|could|can|not|www|com|org|gov|any|then|some|many|few|http|https|acquia|when|what|where|which|whose|who|its|dear|need|like|would|new|see|look|all|none|[0-9][0-9]*)$' |sort |uniq -c |sort -nr |head -20

echo "Top quotes:"
cat test.out |egrep -o '"[^"]{10,100}*"' |sort |uniq -c |sort -nr |head -10

# Get top tags
echo "Top root causes:"
cat $tmpout |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { foreach ($ticket->tags as $tag) { echo $tag . "\n"; } }' |grep "^rc" |sort |uniq -c |sort -nr |head -20

exit
#########################
#########################  THE END  #######################
#########################

# From $tmpout
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



