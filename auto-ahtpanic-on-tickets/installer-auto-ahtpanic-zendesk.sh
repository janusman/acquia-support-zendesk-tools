#!/bin/bash

# installer-auto-ahtpanic-zendesk.sh
# 
# 2019-06-14
#
#
# Installer for ticket-watcher-and-auto-ahtpanic
#
# This is supposed to install the script in Bastion so that it can run
# for all of Support. It will ingest ZD tickets and run ahtpanic.sh on
# them.

INSTALL_FOLDER=$HOME/auto-ahtpanic-zendesk

if [ -r $INSTALL_FOLDER ]
then
  echo "Already installed at $INSTALL_FOLDER"
  exit 1
fi
  
echo "Creating folder at $INSTALL_FOLDER"

mkdir $INSTALL_FOLDER
cd $INSTALL_FOLDER

# Clone git repos
git clone git@github.com:janusman/Support-Tools.git -b ahtpanic-improvements-2017-11
git clone git@github.com:janusman/acquia-support-zendesk-tools.git

# Add Zendesk API token.
echo -n "Enter Zendesk API token (format = example@acquia.com/token:XXXXXXXXXXX): "
read token
echo "$token" >acquia-support-zendesk-tools/creds.txt

## Add some commands to the bin folder
mkdir bin
cd bin 

cat <<EOF >aht
#!/bin/bash

/vol/ebs1/ahsupport/aht/prod/ahtools \$@
EOF
cat <<EOF >ahtpanic.sh
#!/bin/bash

$INSTALL_FOLDER/Support-Tools/bin/ahtpanic.sh \$@
EOF
cat <<EOF >run-ticket-watcher
#!/bin/bash

$INSTALL_FOLDER/acquia-support-zendesk-tools/auto-ahtpanic-on-tickets/run-ticket-watcher
EOF

# Install ansi2html
curl http://www.pixelbeat.org/scripts/ansi2html.sh >ansi2html

# Make commands in $INSTALL_FOLDER/bin executable
chmod +x ansi2html aht ahtpanic.sh ansi2html run-ticket-watcher

cat <<EOF

================================
INSTALLATION DONE!

Installation path: $INSTALL_FOLDER
  Commands are in: $INSTALL_FOLDER/bin

You can run the monitoring script this way:

export PATH=\$PATH:$INSTALL_FOLDER/bin
run-ticket-watcher
EOF
