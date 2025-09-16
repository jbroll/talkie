# Simple Makefile for Talkie Tcl

.PHONY: all build clean run test

all: build

build:
	$(MAKE) -C pa
	$(MAKE) -C vosk
	$(MAKE) -C audio
	$(MAKE) -C uinput

clean:
	$(MAKE) -C pa clean
	$(MAKE) -C vosk clean
	$(MAKE) -C audio clean
	$(MAKE) -C uinput clean

run: build
	./talkie.tcl

test: build
	./talkie.tcl
