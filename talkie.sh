#!/bin/bash
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
        # Set up environment for GPU-accelerated sherpa-onnx with onnxruntime-openvino
        export LD_LIBRARY_PATH="$HOME/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
        export ORT_PROVIDERS="OpenVINOExecutionProvider,CPUExecutionProvider"
        export OV_DEVICE="GPU"
        export OV_GPU_ENABLE_BINARY_CACHE="1"
        
        # Activate virtual environment and run talkie.py
        cd "$HOME/src/talkie"
        . bin/activate
        python talkie.py "$@"
esac

exit 0
