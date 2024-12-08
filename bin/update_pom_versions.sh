#!/bin/bash

set -eu -o pipefail
IFS=$'\n\t'

cd $(readlink -f "$(dirname "$0")") # Example command to move to dir containing script.

MODE=""
UPDATE_VERSION_MODE="UPDATE_VERSION"

while [[ $# > 0 ]]
do
    key="$1"
    set +u
    value="$2"
    set -u

    case $key in
        --update-version)
            MODE=$UPDATE_VERSION_MODE
            shift
            ;;
        -u)
            MODE=$UPDATE_VERSION_MODE
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

ACTION_TAKEN="false"
if [ "$MODE" == "$UPDATE_VERSION_MODE" ]; then
    ACTION_TAKEN="true"
    latest_version=`zind -g pom.xml -t version -t SNAPSHOT | cut -d'>' -f2 | cut -d '<' -f1 | sort | uniq | sort -t '.' -k1,1nr -k2,2nr -k3,3nr | head -n 1`
    versions=`zind -g pom.xml -t version -t SNAPSHOT | cut -d'>' -f2 | cut -d '<' -f1 | sort | uniq | grep -v "$latest_version"` || true | xargs -n 9999

    read -r -a version_array <<< "$versions"
    for version in "${version_array[@]}"; do
        echo "Changing $version -> $latest_version"
    done

    rsed "s/$version/$latest_version/g"
fi

if [ "$ACTION_TAKEN" == "false" ]; then
    echo "No mode or invalid mode set: [$MODE]"
    exit 1
fi
