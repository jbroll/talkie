# Makefile for GEC (Grammar Error Correction) OpenVINO bindings

.PHONY: all clean test

CRITCL = /home/john/bin/critcl

# OpenVINO paths
OV_LIB = /home/john/pkg/openvino-src/bin/intel64/Release
NPU_LIB = /home/john/pkg/linux-npu-driver/build/lib

all:
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) $(CRITCL) -pkg gec.tcl

clean:
	rm -rf lib

test: all
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) tclsh test_gec.tcl
