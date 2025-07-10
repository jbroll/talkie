#!/bin/sh
#

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
        $HOME/bin/talkie
esac

exit 0
