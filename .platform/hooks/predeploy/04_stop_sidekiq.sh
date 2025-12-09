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
  echo "Stopping Sidekiq (PID: $PID) before deployment"
  logger -t "sidekiq" "Stopping Sidekiq (PID: $PID) before deployment"
  
  # Graceful shutdown
  su -s /bin/bash -c "kill -TERM $PID" $EB_APP_USER || true
  
  # Wait for shutdown (up to 60 seconds for long-running jobs)
  for i in {1..60}; do
    if ! ps -p $PID > /dev/null 2>&1; then
      echo "Sidekiq stopped successfully"
      logger -t "sidekiq" "Sidekiq stopped successfully"
      su -s /bin/bash -c "rm -f $SIDEKIQ_PID" $EB_APP_USER
      exit 0
    fi
    sleep 1
  done
  
  # Force kill if still running after 60 seconds
  echo "Force stopping Sidekiq after timeout"
  logger -t "sidekiq" "Force stopping Sidekiq after timeout"
  su -s /bin/bash -c "kill -9 $PID" $EB_APP_USER || true
  su -s /bin/bash -c "rm -f $SIDEKIQ_PID" $EB_APP_USER
else
  echo "No Sidekiq process to stop"
  logger -t "sidekiq" "No Sidekiq process to stop"
fi