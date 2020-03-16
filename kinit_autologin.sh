#!/bin/bash

USER="$1"
LOGIN_FILE="$2"

while true; do
  echo "[$(date)] Logging in"
  cat $LOGIN_FILE | kinit --password-file=STDIN $USER

  TICKETS=`klist --json`
  if [ "$TICKETS" -eq "{}" ]; then
    echo "Ticket allocation failed.  Short sleep"
    sleep 60
  else
    echo "Received ticket"
    echo "$TICKETS"
    sleep 3600
  fi
done
