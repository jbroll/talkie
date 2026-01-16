# Makefile for WordPiece tokenizer package

.PHONY: all clean test

CRITCL = /home/john/bin/critcl

all:
	$(CRITCL) -pkg wordpiece.tcl

clean:
	rm -rf lib

test: all
	tclsh test_wordpiece.tcl
