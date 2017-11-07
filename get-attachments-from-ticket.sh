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
curl -su $credentials https://acquia.zendesk.com/api/v2/tickets/${ticket}/comments.json >$tmpout

if [ `grep -c "Couldn't authenticate you" $tmpout` -eq 1 ]
then
  errmsg "Couldn't authenticate against Zendesk. Make sure $CREDS_FILE has the correct credentials."
  exit 1
fi

# Do some maintenance to keep temp folders manageable
header "Housekeeping..."
echo "Deleting really old folders (>100 days)"
find old -maxdepth 1 -type d -mtime +90 -name 'z*' -print -exec rm -rf "{}" \;

echo "Moving older z* folders to old/"
find -maxdepth 1 -type d -ctime +30 -name 'z*' -print -exec mv "{}" old/ \;

# Clean out and create destination folder
DEST_FOLDER=z${1}
rm -rf $DEST_FOLDER
mkdir -p $DEST_FOLDER
cd $DEST_FOLDER
echo "Created destination folder $DEST_FOLDER/"

# Process comments and download attachments
header "Processing ticket"
cat $tmpout |php -r '

function sep() {
  return str_repeat("=", 70) . "\n";
}
$result = json_decode(trim(stream_get_contents(STDIN)));
$attachments = array();
$cores = array();

foreach ($result->comments as $cid => $comment) {
  # Show first comment...
  if ($cid == 0) {
    echo "\nFirst comment in ticket: {$comment->created_at}\n" . sep() . wordwrap($comment->body) . "\n" . sep() . "\n";
  }
  
  # Gather attachments
  if ($comment->attachments) {
    foreach ($comment->attachments as $attachment) {
      $attachments[$attachment->file_name] = $attachment->content_url;
    }
  }
  
  # Look for core IDs
  if ($comment->body) {
    $ok = preg_match_all("/[A-Z][A-Z][A-Z][A-Z]-[0-9][0-9][0-9][0-9][0-9][0-9]*(\.[a-z0][a-z1][a-zA-Z0-9]*\.[a-zA-Z0-9]*|_[a-zA-Z0-9]*|)/", $comment->body, $matches, PREG_SET_ORDER);
    if ($ok) {
      foreach ($matches as $match) {
        $core = $match[0];
        $cores[$core] = $core;
      }
    }
  }
  
}

echo "\nLast comment in ticket: {$comment->created_at}\n" . sep() . wordwrap($comment->body) . "\n" . sep() . "\n";

# Output detected cores
#echo "cores=" . implode(",", array_keys($cores)) . "\n";

# Download files!
$final_files = array();
system("mkdir ticketfiles 2>/dev/null");
foreach ($attachments as $filename => $url) {
  
  if (! preg_match("/.*\.(txt|xml|zip)$/", $filename)) {
    echo "Skipping download of $filename...\n";
    continue;
  }
  
  # TODO: Remove some attachments based on filename extenstion (like .diff?)
  
  # Use L because we need to follow the redirect
  $cmd = "curl -sL $url -o \"ticketfiles/$filename\"";
  $ok = system($cmd);
  if ($ok === FALSE) {
    echo "# Error! Could not download file from $url\n";
  }
  $final_files[] = "ticketfiles/$filename";
  echo "Downloaded $filename\n";
}

# Write out scripts for each core.
foreach ($cores as $core) {
  $script = "#!/bin/bash\ncheck-solr-config.sh '$ticket' $core ticketfiles\n";
  file_put_contents("{$core}.sh", $script);
  echo "Wrote script to {$core}.sh\n";
}
' | egrep --color '^|[A-Z][A-Z][A-Z][A-Z]-[0-9][0-9][0-9][0-9][0-9][0-9]*(\.[a-z0][a-z1][a-zA-Z0-9]*\.[a-zA-Z0-9]*|_[a-zA-Z0-9]*|)'

# unzip any applicable files
folder=`pwd`
cd ticketfiles
for nom in *zip
do
  if [ "$nom" != "*zip" ]
  then
    echo "Unzipping $nom..."
    unzip $nom && rm $nom
  fi
done

# Change any .xml.txt files to .xml
for nom in *.xml.txt
do
  if [ "$nom" != "*.xml.txt" ]
  then
    name_without_txt=`echo "$nom" | sed -e 's/.txt$//'`
    echo "Renaming $nom ==> $name_without_txt"
    mv "$nom" $name_without_txt
  fi
done

cd ..
header "DONE"
echo ""
echo "  ${COLOR_GREEN}Created destination folder $DEST_FOLDER/"
echo "  All applicable attachments were downloaded to $DEST_FOLDER/ticketfiles:"
ls -l ticketfiles | awk 'NR>1 {print "    " $0 }'
echo ""
echo "  You can now run these scripts in this folder to process each mentioned index:"
ls *.sh | awk '{print "    " $0 }'

echo 'for nom in *.sh; do bash $nom; done' >run-all && chmod +x run-all
echo ""
echo "  Or, you can process all cores now by typing this:"
echo "      cd z${ticket}; ./run-all"
echo "$COLOR_NONE"
