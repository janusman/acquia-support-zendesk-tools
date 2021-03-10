#!/bin/bash
# parse-solr-config-ticket.sh
# https://gist.github.com/janusman/e6365dc999c41a133cf6

# See http://linuxtidbits.wordpress.com/2008/08/11/output-color-on-bash-scripts/
COLOR_RED=$(tput setaf 1) #"\[\033[0;31m\]"
COLOR_YELLOW=$(tput setaf 3) #"\[\033[0;33m\]"
COLOR_GREEN=$(tput setaf 2) #"\[\033[0;32m\]"
COLOR_GRAY=$(tput setaf 7) #"\[\033[2;37m\]"
COLOR_NONE=$(tput sgr0) #"\[\033[0m\]"

function errmsg() {
  echo "${COLOR_RED}$1${COLOR_NONE}"
}

function warnmsg() {
    echo "${COLOR_YELLOW}$1${COLOR_NONE}"
}

function header() {
  echo ""
  echo "${COLOR_GRAY}._____________________________________________________________________________"
  echo "|${COLOR_GREEN}  $1${COLOR_NONE}"
}


if [ ${1:-x} = x ]
then
  echo "${COLOR_YELLOW}Usage: $0 ticket-number"
  echo 
  echo "Tries to automate custom configuration tickets by downloading all attachments"
  echo " and detect any core IDs mentioned in ticket comments.$COLOR_NONE"
  exit 0
fi

ticket=$1
tmpout=/tmp/output.json
CREDS_FILE=creds.txt

if [ ! -r creds.txt ]
then
  errmsg "Place a one-liner into a creds.txt file, with this information:"
  errmsg "  YourEmail@acquia.com:PassWordUsedToLogIntoZendesk"
  errmsg "Or, a ZD API token string:"
  errmsg "  YourEmail@acquia.com/token:TokenString$COLOR_NONE"
  exit 0
fi
credentials=`cat $CREDS_FILE`
curl -su $credentials https://acquia.zendesk.com/api/v2/tickets/${ticket}/comments.json
