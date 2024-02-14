#!/bin/bash

SKIP_BUILD=false

# Parse command line
while [[ $# > 0 ]]
do
    key="$1"
    value="$2"

    case $key in
        -s)
            SKIP_BUILD=true
            ;;
        --skip)
            SKIP_BUILD=true
            ;;
        -v)
            set -x
            ;;
        *)
            echo "Unknown option passed: $key"
            exit 1
            ;;
    esac
    shift
done

if [ "$skip_build" == "true" ]; then
    ./mvnw -T4 clean install -DskipTests
fi

/opt/nifi/bin/nifi.sh stop

# Get backup version
current_version=`ls -1 /opt/ | grep nifi | grep backup | sort -r | head -n 1 | cut -d'-' -f1 | cut -c '7-'`
if [ "$current_version" == "" ]; then
  current_version=0
fi
next_version=$((current_version+1))

nifi_name=`readlink -f /opt/nifi | xargs basename`
sudo mv "/opt/$nifi_name" "/opt/backup${next_version}-$nifi_name"

build_dir=`ls -1 nifi-assembly/target/ | grep -e nifi.*bin | grep -v zip | xargs basename`
build_name=`ls -1 nifi-assembly/target/$build_dir | xargs basename`
sudo cp -r nifi-assembly/target/$build_dir/$build_name /opt/
sudo /bin/bash -c "cd /opt && ln -sf $build_name nifi"
sudo chown -R aethier /opt/$build_name

cp -r "/opt/backup${next_version}-$nifi_name/conf/*" /opt/nifi/conf/
