#!/bin/sh

if [ "${1:-x}" = x ]
then
  echo "Usage: $0 [search string]"
  echo 
  echo "Examples"
  cat <<EOF
  sh tickets-analysis.sh outage
  sh tickets-analysis.sh stampede
  sh tickets-analysis.sh PDOException
  sh tickets-analysis.sh tags:rc:search
  sh tickets-analysis.sh tags:rcs:dos_ddos_attack
EOF
  exit 0
fi

tmpout=/tmp/output.json
CREDS_FILE=creds.txt

if [ ! -r creds.txt ]
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
#curl -su $credentials "https://acquia.zendesk.com/api/v2/incremental/tickets.json?start_time="`php -r 'echo time()-(300*24);'` >ticket-export.json

#curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json?query=tags:rcs:${1}" >ticket-export.json
curl -su $credentials "https://acquia.zendesk.com/api/v2/search.json" -G --data-urlencode "query=type:ticket created>2016-01-01 -tags:ticket:submitted_ops -tags:ticket:proactive ${1}" >ticket-export.json

echo "Random sampling of some ticket titles:"
cat ticket-export.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { echo "   #" . $ticket->id ."  " . $ticket->subject . "\n"; }' |sort -R |head -10
echo ""

cat ticket-export.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { echo $ticket->subject . "\n"; echo $ticket->description . "\n"; };' >test.out 

echo "Top mentioned words:"
cat test.out |tr 'A-Z' 'a-z' |sed -e 's/[^a-z0-9A-Z]/ /g' -e 's/  */ /g' -e 's/ /\n/g' |sed -e '/^$/d' |egrep -v '^(.|..|for|the|have|here|there|and|but|was|been|you|she|they|them|this|has|with|without|may|that|those|are|your|mine|our|ours|yours|can|from|will|please|thank|thanks|hello|were|regards|could|can|not|www|com|org|gov|any|then|some|many|few|http|https|acquia|when|what|where|which|whose|who|its|dear|need|like|would|new|see|look|all|none|[0-9][0-9]*)$' |sort |uniq -c |sort -nr |head -20

echo "Top quotes:"
cat test.out |egrep -o '"[^"]{10,100}*"' |sort |uniq -c |sort -nr |head -10

# Get top tags
echo "Top root causes:"
cat ticket-export.json |php -r '$result = json_decode(trim(stream_get_contents(STDIN))); foreach ($result->results as $ticket) { foreach ($ticket->tags as $tag) { echo $tag . "\n"; } }' |grep "^rc" |sort |uniq -c |sort -nr |head -20

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



