#!/bin/bash
if pgrep -f "telegram:redminebot:poller" > /dev/null
then
    echo "Telegram poller already running"
else
  cd $(dirname -- "$0");
  cd ../..
  RAILS_ENV=production rake telegram:redminebot:poller &
fi