#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

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

cd ./nifi

/opt/nifi/bin/nifi.sh stop &

if [ "$SKIP_BUILD" == "false" ]; then
    ./mvnw -T4 clean install -DskipTests -Dspotbugs.skip=true -Dcheckstyle.skip -Dpmd.skip=true -Dmaven.javadoc.skip=true -Dmaven.test.skip -Denforcer.skip=true -Drat.skip=true
fi

# Get backup version
next_version=`ls -1 /opt/ | grep nifi | grep backup | sort -r | head -n 1 | cut -d'-' -f1 | cut -c '7-'`
nifi_name=`readlink -f /opt/nifi | xargs basename`

build_dir=`ls -1 nifi-assembly/target/ | grep -e nifi.*bin | grep -v zip | xargs basename`
build_name=`ls -1 nifi-assembly/target/$build_dir | xargs basename`
if [ -d "/opt/$build_name" ]; then
    rm -f /opt/nifi/conf/archive/*
    /opt/nifi/bin/nifi.sh stop

    next_version=$((next_version+1))
    sudo mv "/opt/$nifi_name" "/opt/backup${next_version}-$nifi_name"
    echo "Backed up /opt/$nifi_name to /opt/backup${next_version}-$nifi_name"
fi

sudo cp -r nifi-assembly/target/$build_dir/$build_name /opt/
sudo /bin/bash -c "cd /opt && ln -sf $build_name nifi"

if [ -n "$next_version" ]; then
    echo "Copying configs from /opt/backup${next_version}-$nifi_name"
    sudo cp -r /opt/backup${next_version}-$nifi_name/conf/* /opt/nifi/conf/
fi
sudo chown -R aethier /opt/$build_name
