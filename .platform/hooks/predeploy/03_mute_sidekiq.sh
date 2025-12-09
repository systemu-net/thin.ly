#!/usr/bin/env bash
set -e

EB_APP_USER=$(/opt/elasticbeanstalk/bin/get-config container -k app_user)
EB_SCRIPT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k script_dir)
EB_SUPPORT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k support_dir)
EB_APP_PID_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_pid_dir)

. $EB_SUPPORT_DIR/envvars
. $EB_SCRIPT_DIR/use-app-ruby.sh

SIDEKIQ_PID=$EB_APP_PID_DIR/sidekiq.pid

if [ -f $SIDEKIQ_PID ]; then
  PID=$(cat $SIDEKIQ_PID)
  echo "Sending USR1 to Sidekiq (PID: $PID) to stop processing new jobs"
  logger -t "sidekiq" "Sending USR1 to Sidekiq (PID: $PID) to stop processing new jobs"
  su -s /bin/bash -c "kill -USR1 $PID" $EB_APP_USER || true
  echo "Sidekiq will finish current jobs before shutdown"
  logger -t "sidekiq" "Sidekiq will finish current jobs before shutdown"
else
  echo "No Sidekiq PID file found, nothing to quiet"
  logger -t "sidekiq" "No Sidekiq PID file found, nothing to quiet"
fi