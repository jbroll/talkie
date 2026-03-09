CRITCL = /home/john/bin/critcl
OV_LIB = /home/john/pkg/openvino-src/bin/intel64/Release
NPU_LIB = /home/john/pkg/linux-npu-driver/build/lib

all:
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) $(CRITCL) -pkg ov.tcl

clean:
	rm -rf lib

test: all
	LD_LIBRARY_PATH=$(NPU_LIB):$(OV_LIB) tclsh test_ov.tcl
