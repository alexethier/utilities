#!/bin/bash
# Example way to parse bash arguments in a more general way.

# Parse command line
while [[ $# > 0 ]]
do
    key="$1"
    value="$2"

    # If arguments come in the form a=b
    if [[ $1 == *'='* ]]
    then
        IFS='=' read -ra key_pair <<< "$1"
        key="${key_pair[0]}"
        value="${key_pair[1]}"
    fi

    echo "debug -- KEY IS |$key|"
    echo "debug -- VALUE IS |$value|"

    case $key in
        --example-two)
            EXAMPLE_TWO="$value"
            shift
            ;;
        --example)
            EXAMPLE="flag_setting"
            ;;
        *)
            echo "Unknown option passed: $key"
            exit 1
            ;;
    esac
    shift
done

echo "Example Two: |$EXAMPLE_TWO|"
echo "Example: |$EXAMPLE|"
