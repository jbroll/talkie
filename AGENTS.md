# AGENTS.md - Guidance for AI Coding Agents

## Build/Test Commands
- **Build**: `make` or `make build` (builds C extensions in pa/, vosk/, audio/, uinput/)
- **Run**: `cd src && ./talkie.tcl`
- **Test All**: `cd src/tests && ./all_tests.tcl`
- **Test Single**: `cd src/tests && tclsh -c "package require tcltest; source <test_file>.test"`
- **Clean**: `make clean`

## Architecture
- **Language**: Tcl/Tk with C extensions (via critcl)
- **Entry Point**: `src/talkie.tcl`
- **Core Modules**: config.tcl, audio.tcl, engine.tcl, coprocess.tcl, ui-layout.tcl
- **C Bindings**: pa/ (PortAudio), vosk/ (Vosk speech), audio/ (processing), uinput/ (keyboard)
- **Config Files**: `~/.talkie.conf` (JSON), `~/.talkie` (state JSON)
- **State Management**: Trace-based with global `::transcribing` variable

## Code Style (Tcl)
- **Minimal Code**: Prefer one-liners over bloated functions
- **Global State**: Use `::namespace::variable` convention (e.g., `::config(key)`, `::transcribing`)
- **Traces**: Use variable traces for state synchronization
- **Error Handling**: `catch {cmd} result` with stderr logging via `bgerror`
- **File I/O**: Use `jbr::unix` commands (`cat`, `echo`) for simplicity
- **Naming**: Snake_case for procs (e.g., `config_save`), lowercase for variables
- **No Comments**: Code should be self-explanatory; avoid unnecessary comments
