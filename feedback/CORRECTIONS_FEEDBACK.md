Capturing User Corrections for STT in Terminal-Based AI CLIs (Claude Code)
Problem Statement

An STT system injects recognized text directly into an active Linux terminal (via uinput).
Users may correct the text interactively in the TTY/terminal emulator before pressing Enter.
Those corrections occur inside the target application (e.g., Claude Code in xfce4-terminal) and are therefore not directly visible to the STT system.

Goal: capture user corrections non-invasively, friction-free, and reliably, to build a feedback loop for STT learning.
Target environment: Void Linux, xfce4-terminal, Claude Code CLI.

Key Constraints and Observations

Once text is injected, the terminal/application owns the edit buffer.

Linux provides no automatic “edit history” feedback channel.

Capturing individual keystrokes is unnecessary; the final accepted line is the correct learning signal.

Claude Code runs in a PTY, reads stdin line-by-line, and does not expose input-level hooks.

Claude Code does provide prompt hooks, but they operate at the semantic / LLM layer, not at the terminal input layer.

Claude Code Hooks: What They Do and Don’t Do
What prompt hooks provide

Access to the final user message as sent to the model

Timing and session context

Ability to modify or annotate prompts

What prompt hooks do not provide

Raw stdin or keystroke events

Visibility into user edits before submission

Direct linkage to injected STT text

Conclusion: Prompt hooks are downstream of input acceptance. They cannot observe corrections by themselves, but they can consume correction data obtained elsewhere.

Primary Technical Approaches Considered
1. Line-Oriented stdin Interception (Recommended, Most Robust)

Intercept libc I/O (e.g., read(), readv()) using LD_PRELOAD and capture stdin content when a newline is returned.

Properties

Captures exactly what Claude Code receives

Zero UX impact

Application-agnostic

Works naturally with PTYs and xfce4-terminal

Outcome

Final corrected line is available

Compare against injected STT text to learn corrections

2. PTY Proxy / Expect-Style Wrapper

Run the shell or Claude Code behind a PTY proxy that mediates all input/output.

Properties

Full bidirectional visibility

Clean architectural separation

Tradeoff

Requires launching sessions inside the proxy

Heavier than necessary for this use case

3. Shell Line-Editor Hooks (Not Applicable Here)

Bash (bind -x) or Zsh (zle) hooks can capture accepted lines, but:

Claude Code is not a shell

These hooks do not fire inside Claude’s own prompt loop

4. evdev / keystroke-level capture (Rejected)

Complex

Fragile

Reimplements line discipline logic

Inferior to line-level capture

Alternative Strategy: Correlating STT Logs with Claude Prompt Hooks

If direct stdin interception is undesirable, a probabilistic matching approach is viable.

Method

Log each STT injection:

Injected text

Monotonic timestamp

Target PTY/session

Observe Claude prompt hooks:

Final prompt text

Timestamp

Session context

Match injections to prompts using:

Temporal proximity

Text similarity (edit distance, n-grams)

Heuristics (length, prefix/suffix)

Enhancements

Prefer false negatives over false positives

Ignore ambiguous matches

Optionally inject an invisible marker (e.g., zero-width Unicode) into STT text to improve correlation

Tradeoffs

Less precise than stdin interception

Lower engineering cost

Claude-specific

Recommended Architecture

Best overall solution

Capture finalized input at the stdin boundary (line-oriented interception)

Diff against injected STT text

Feed corrections into STT learning logic

Optional augmentation

Use Claude prompt hooks to:

Consume learned corrections

Adapt prompts dynamically

Annotate input provenance