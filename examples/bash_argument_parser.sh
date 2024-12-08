#!/bin/bash

# Example bash boilerplate to create clean scripts.
set -eu -o pipefail
IFS=$'\n\t'

cd $(readlink -f "$(dirname "$0")") # Example command to move to dir containing script.

EXAMPLE=""
EXAMPLE_TWO=""

# Example way to parse bash arguments in a more general way.

# Parse command line
while [[ $# > 0 ]]
do
    key="$1"
    set +u
    value="$2"
    set -u

    case $key in
        --example-two)
            EXAMPLE_TWO="$value"
            shift
            ;;
        --example)
            EXAMPLE="flag_setting"
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

COMMAND_SAVE=~/.aetmp/example.txt
if [ -f $COMMAND_SAVE ]; then
    if [ ! -n "$EXAMPLE_TWO" ]; then
        EXAMPLE_TWO=`cat $COMMAND_SAVE | grep "EXAMPLE_TWO" | cut -d '=' -f2`
    fi
fi

mkdir -p ~/.aetmp
echo "EXAMPLE_TWO=$EXAMPLE_TWO" > $COMMAND_SAVE

if [ -z "${EXAMPLE_TWO}" ]; then
  echo "Error: EXAMPLE_TWO is not set, use --example-two <value> to set." >&2
  exit 1
fi

echo "Example Two: |$EXAMPLE_TWO|"
echo "Example: |$EXAMPLE|"
