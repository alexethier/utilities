#!/bin/bash

# Script to automate modification of DataBrick's objects based on the REST api: https://docs.databricks.com/dev-tools/api/
# Note the Python client did not work for me.

# Requires jq - $ brew install jq

set -e -o pipefail
IFS=$'\n\t'

FILTER=""
# Parse command line
while [[ $# > 0 ]]
do
    key="$1"
    value="$2"

    case $key in
        -f)
            FILTER="$value"
            shift
            ;;
        --filter)
            FILTER="$value"
            shift
            ;;
        -v)
            set -x
            ;;
        --verbose)
            set -x
            ;;
        *)
            echo "Unknown option passed: $key"
            exit 1
            ;;
    esac
    shift
done

if [ -z "$FILTER" ];then
  echo "Missing --filter argument."
  exit 1
fi

function check_auth() {
  if [ -z "$DATABRICKS_TOKEN" ]; then
    echo "Missing databricks PAT - export env. variable: DATABRICKS_TOKEN"
    exit 1
  fi
}

function get() {
  check_auth
  curl -X GET --header "Authorization: Bearer $DATABRICKS_TOKEN" https://deliverr.cloud.databricks.com$1 --no-progress-meter
}

function post() {
  check_auth
  curl -X POST --header "Authorization: Bearer $DATABRICKS_TOKEN" https://deliverr.cloud.databricks.com$1 --no-progress-meter -d "$2"
}

function put() {
  check_auth
  curl -X PUT --header "Authorization: Bearer $DATABRICKS_TOKEN" https://deliverr.cloud.databricks.com$1 --no-progress-meter -d "$2"
}

function patch() {
  check_auth
  curl -X PATCH --header "Authorization: Bearer $DATABRICKS_TOKEN" https://deliverr.cloud.databricks.com$1 --no-progress-meter -d "$2"
}

function list_jobs() {
  if [ -z "$1" ]; then
    offset=0
    limit=25
    current_jobs="[]"
  else
    offset="$1"
    limit="$2"
    current_jobs="$3"
  fi
  next_jobs=`get "/api/2.1/jobs/list?limit=${limit}&offset=${offset}" | jq ".jobs"`
  num_jobs=`echo $next_jobs | jq ". | length"`
  if [[ "$num_jobs" -gt "0" ]]; then
    total_jobs=`echo "${current_jobs} ${next_jobs}" | jq -s add`
    # Concatenate output to current output and query next page
    # Ugly but works at small scales
    list_jobs $((offset + num_jobs)) 20 "$total_jobs"
  else
    echo "$current_jobs"
  fi
}

function filter_jobs() {
  filter="$1"
  input_jobs="$2"
  filtered_jobs=`echo $input_jobs | jq -r ".[] | select(.settings.name | contains(\"$filter\")) | .job_id"`
  echo "$filtered_jobs"
}

function get_job() {
  get "/api/2.1/jobs/get?job_id=$1"
}

function get_job_name() {
  get_job "$1" | jq -r '.settings.name'
}

function get_job_permissions() {
  get "/api/2.0/permissions/jobs/$1"
}

function put_job_permissions() {
  update_json='{"access_control_list":[{"group_name":"data-science-run","permission_level":"CAN_MANAGE_RUN"},{"user_name":"aethier@deliverr.com","permission_level":"IS_OWNER"}]}'
  output=`put "/api/2.0/permissions/jobs/$1" "${update_json}"`
  echo "Completed setting job permissions for $1"
}

function get_filtered_jobs() {
  all_jobs=`list_jobs`
  filtered_jobs=`filter_jobs "$1" "$all_jobs"`
  echo "$filtered_jobs"
}

function put_batch_job_permissions() {
  for job_id in $1
  do
    echo "Updating permissions for $(get_job_name $job_id)"
    put_job_permissions $job_id
  done
}

function main() {
  oce_job_ids=`get_filtered_jobs "$FILTER"`
  put_batch_job_permissions "$oce_job_ids"
}

main
