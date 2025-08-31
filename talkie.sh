#!/bin/bash
#

# Check if first argument is a flag (starts with --) or a command
if [[ "$1" == --* ]]; then
    # First argument is a flag, pass all arguments to talkie.py
    cd "$HOME/src/talkie"
    . bin/activate
    python talkie.py "$@"
else
    # First argument is a command
    CMD=$1; shift
    
    case $CMD in
        state) cat $HOME/.talkie ;;
        toggle)
            STATE=`cat ~/.talkie | jq .transcribing`
            case $STATE in
                false) $0 start ;;
                true) $0 stop ;;
            esac
            ;;
        start) echo '{"transcribing": true}' > $HOME/.talkie ;;
        stop) echo '{"transcribing": false}' > $HOME/.talkie ;;
        
        *)
            # Default: run talkie.py with all original arguments
            # Environment setup is now handled in talkie.py based on selected engine
            cd "$HOME/src/talkie"
            . bin/activate
            python talkie.py "$@"
    esac
fi

exit 0
