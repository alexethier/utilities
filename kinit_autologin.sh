#!/bin/bash

# In case the calling process spams autorestarts have a sleep up front to prevent spamming the krb server.
sleep 1

USER="$1"
LOGIN_FILE="$2"
EXPIRES="0"

while true; do

  TICKETS=`klist --json`
  if [ "$TICKETS" -eq "{}" ]; then
    echo "No ticket found."
  else
    echo "Existing ticket"
    echo "$TICKETS"
    # Assumes we only ever have one ticket, or at least the first one is the one we care about
    EXPIRES=`klist --json | jq -r '.tickets[0]["Expires"]' | xargs -I {} date --date="{}" +"%s" | xargs -I {} /bin/bash -c 'echo "$(({} - $(date +%s)))"'`
    echo "Expires in $EXPIRES"
  fi

  if [ "$EXPIRES" -lt "5000" ]; then
    echo "[$(date)] Logging in with $USER and credentials $LOGIN_FILE"
    cat $LOGIN_FILE | kinit --password-file=STDIN $USER
  else
    echo "Valid ticket exits, long sleep"
    sleep 2000 # If initial tests work we should dynamically sleep based on the remaining expiration time
  fi

  TICKETS=`klist --json`
  if [ "$TICKETS" -eq "{}" ]; then
    echo "Failed getting ticket, short sleep"
    sleep 60
  fi
done
