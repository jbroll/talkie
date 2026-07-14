# Simple Makefile for sherpa-onnx package

.PHONY: all clean test

CRITCL = /home/john/bin/critcl

all:
	$(CRITCL) -pkg sherpa.tcl

clean:
	rm -rf lib

test: all
	LD_LIBRARY_PATH=$(HOME)/.local/lib tclsh tests/sherpa.test
