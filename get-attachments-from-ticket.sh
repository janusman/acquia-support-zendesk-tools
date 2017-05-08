#!/bin/sh
# parse-solr-config-ticket.sh
# https://gist.github.com/janusman/e6365dc999c41a133cf6

if [ ${1:-x} = x ]
then
  echo "Usage: $0 [ticket-id]"
  echo 
  echo "Tries to automate custom configuration tickets by downloading all attachments"
  echo " and detect any core IDs mentioned in ticket comments."
  exit 0
fi

ticket=$1
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
credentials=`cat $CREDS_FILE`
curl -su $credentials https://acquia.zendesk.com/api/v2/tickets/${ticket}/comments.json >$tmpout

if [ `grep -c "Couldn't authenticate you" $tmpout` -eq 1 ]
then
  echo "Couldn't authenticate against Zendesk. Make sure $CREDS_FILE has the correct credentials."
  exit 1
fi

# Do some maintenance to keep temp folders manageable
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
'

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
echo ""
echo "====================================================="
echo "| DONE!!"
echo "====================================================="
echo ""
echo "Created destination folder $DEST_FOLDER/"
echo "  All applicable attachments were downloaded to $DEST_FOLDER/ticketfiles:"
ls -l ticketfiles | awk 'NR>1 {print "    " $0 }'
echo ""
echo "  You can now run these scripts in this folder to process each mentioned index:"
ls *.sh | awk '{print "    " $0 }'
echo ""
