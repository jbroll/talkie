# Makefile for GEC (Grammar Error Correction) pipeline
# OpenVINO bindings are in ../ov/; this Makefile runs pipeline tests only.

.PHONY: all clean test test_homophone test_punctcap test_pipeline

OV_LIB = /home/john/pkg/openvino-src/bin/intel64/Release
NPU_LIB = /home/john/pkg/linux-npu-driver/build/lib

all:

clean:

test: test_homophone test_punctcap test_pipeline

test_homophone:
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) tclsh test_homophone.tcl

test_punctcap:
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) tclsh test_punctcap.tcl

test_pipeline:
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) tclsh test_pipeline.tcl
