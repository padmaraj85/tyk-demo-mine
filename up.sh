#!/bin/bash

source scripts/common.sh

# check .env file exists
if [ ! -f .env ]
then
  echo "ERROR: Docker environment file missing. Review 'getting started' steps in README.md."
  exit 1
fi

# check dashboard licence defined
if ! grep -q "DASHBOARD_LICENCE=" .env
then
  echo "ERROR: Dashboard licence missing from Docker environment file. Review 'getting started' steps in README.md."
  exit 1
fi

# check that jq is available
command -v jq >/dev/null 2>&1 || { echo >&2 "ERROR: JQ is required, but it's not installed. Review 'getting started' steps in README.md."; exit 1; }

# prevent log file from growing too big - truncate when it reaches over 10000 lines
if [ -f bootstrap.log ] && [  $(wc -l < bootstrap.log) -gt 10000 ]
then
  echo "" > bootstrap.log
fi

# make the context data directory and clear and data from an existing directory
mkdir -p .context-data 1> /dev/null
rm -f .context-data/*

# make sure error flag is not present
rm -f .bootstrap_error_occurred

# clear the .bootstrap/bootstrapped_deployments from deployments
> .bootstrap/bootstrapped_deployments

# ensure Docker environment variables are correctly set before creating containers
if [[ "$*" == *tracing* ]]
then
  set_docker_environment_value "TRACING_ENABLED" "true"
else
  set_docker_environment_value "TRACING_ENABLED" "false"
fi
if [[ "$*" == *instrumentation* ]]
then
  set_docker_environment_value "INSTRUMENTATION_ENABLED" "1"
else
  set_docker_environment_value "INSTRUMENTATION_ENABLED" "0"
fi

# create and run the docker compose command
command_docker_compose="docker-compose -f deployments/tyk/docker-compose.yml"
for var in "$@"
do
  #   the `tyk` deployment is already included, so don't duplicate it
  if [ "$var" != "tyk" ]
  then
    command_docker_compose="$command_docker_compose -f deployments/$var/docker-compose.yml"
  fi
done

echo "Starting containers: $command_docker_compose"
command_docker_compose="$command_docker_compose -p tyk-pro-docker-demo-extended --project-directory $(pwd) up --remove-orphans -d"
eval $command_docker_compose
if [ "$?" != 0 ]
then
  echo "Failure occured when started docker-compose"
  exit
fi

# alway run the tyk bootstrap first
echo "bootstrapping 'tyk' deployment"
deployments/tyk/bootstrap.sh 2>> bootstrap.log
if [ "$?" != 0 ]
then
  echo "Failure during bootstrap of 'tyk'. For details check bootstrap.log"
  exit
fi

# run bootstrap scripts for any feature deployments specified
for var in "$@"
do
  # the `tyk` deployment is already included, so don't duplicate it
  if [ "$var" != "tyk" ]
  then
    echo "bootstrapping: deployments/$var/bootstrap.sh"
    eval "deployments/$var/bootstrap.sh"
    if [ "$?" != 0 ]
    then
      echo "Failure during bootstrap of $var (check deployments/$var/bootstrap.sh). For details check bootstrap.log"
      exit
    else
      echo "$var" >> ./.bootstrap/bootstrapped_deployments
      echo "$var is deployed"
    fi
  fi
done

if [ -f .bootstrap_error_occurred ]
then
  # if an error was logged, report it
  printf "\nError occurred during bootstrap, check bootstrap.log for information\n\n"
else
  # Confirm bootstrap is compelete
  printf "\nTyk-Demo bootstrap completed\n"
  printf "\n----------------------------\n\n"
fi
