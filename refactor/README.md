# Refactor

Refactor is a script that will find and replace token combinations with a wide variety of space separators and casing.  This is best demonstrated via example:

Suppose you run the command:
`./refactor -i /input/file/path -f token1 token2 -r replaced1 replaced2`

This will make the following replacements if they exist:

```
token1_token2 -> replaced1_replaced2
Token1 Token2 -> Replaced1 Replaced2
TOKEN1-token2 -> REPLACED1-replaced2
(hundreds of other possible combinations)
```

Note that casing and character separators are preserved during replacement.  You can pass in more than two find and replace tokens.
The script will not handle cases where the number of replace tokens exceeds the number of find tokens.


# Installation

Either add the bin directory to your PATH variable or:

sudo cp ./bin/refactor /bin

# Usage

refactor --help
