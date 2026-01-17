# Talkie + Claude Code Hook Integration

Captures user corrections to STT-injected text for feedback learning.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Talkie Pipeline                            │
│                                                                      │
│  Vosk ──> GEC ──> textproc ──> uinput ──────────> Terminal          │
│            │                     │                    │              │
│            │                     │                    v              │
│            │                     │            ┌─────────────┐        │
│            │                     │            │ Claude Code │        │
│            │                     │            │ (Ink/React) │        │
│            │                     │            └──────┬──────┘        │
│            v                     v                   │               │
│     ┌──────────────────────────────────────────┐     │               │
│     │     ~/.config/talkie/feedback.jsonl             │<────┘               │
│     │                                          │  UserPromptSubmit   │
│     │  type: gec        (GEC corrections)      │  hook               │
│     │  type: inject     (text sent to uinput)  │                     │
│     │  type: submit     (user's final text)    │                     │
│     └──────────────────────────────────────────┘                     │
└──────────────────────────────────────────────────────────────────────┘
```

**Unified log** captures entire pipeline in one file for easy correlation.

## 1. Unified Feedback Module

New file `src/feedback.tcl` - centralizes all feedback logging:

```tcl
# feedback.tcl - Unified feedback logging for STT correction learning
#
# Logs three event types to ~/.config/talkie/feedback.jsonl:
#   gec    - GEC corrections (vosk output -> GEC output)
#   inject - Text injected via uinput
#   submit - Final text user submitted (from Claude hook)

package require json::write

namespace eval ::feedback {
    variable log_file ""
    variable enabled 1
    variable fd ""
}

proc ::feedback::init {} {
    variable log_file
    variable enabled

    set log_file [file join $::env(HOME) .talkie feedback.jsonl]

    # Ensure directory exists
    file mkdir [file dirname $log_file]

    set enabled 1
}

proc ::feedback::log {type args} {
    variable log_file
    variable enabled

    if {!$enabled || $log_file eq ""} return

    # Build entry with timestamp
    set entry [dict create \
        ts [clock milliseconds] \
        type $type]

    # Add type-specific fields
    foreach {k v} $args {
        dict set entry $k $v
    }

    # Write as JSON line
    if {[catch {
        set fd [open $log_file a]
        puts $fd [json::write object {*}[dict map {k v} $entry {
            if {[string is integer -strict $v]} {
                set v
            } elseif {[string is double -strict $v]} {
                set v
            } elseif {$v eq "true" || $v eq "false"} {
                set v
            } else {
                json::write string $v
            }
        }]]
        close $fd
    } err]} {
        puts stderr "Feedback log error: $err"
    }
}

# Convenience procs for each event type
proc ::feedback::gec {input output} {
    log gec input $input output $output
}

proc ::feedback::inject {text} {
    log inject text $text
}

proc ::feedback::submit {text {session_id ""}} {
    if {$session_id ne ""} {
        log submit text $text session_id $session_id
    } else {
        log submit text $text
    }
}

proc ::feedback::configure {args} {
    variable enabled
    foreach {opt val} $args {
        switch -- $opt {
            -enabled { set enabled $val }
            default { error "Unknown option: $opt" }
        }
    }
}

proc ::feedback::path {} {
    variable log_file
    return $log_file
}

proc ::feedback::clear {} {
    variable log_file
    if {$log_file ne "" && [file exists $log_file]} {
        file delete $log_file
    }
}
```

## 2. Integration Points

### gec.tcl changes

Replace the GEC-specific logging with feedback module:

```tcl
# In ::gec::init, remove:
#   set log_file [file join $::env(HOME) .talkie-gec.log]

# In ::gec::process, replace:
#   log $text $result
# With:
#   ::feedback::gec $text $result

# Remove these procs (now in feedback.tcl):
#   ::gec::log
#   ::gec::log_path
#   ::gec::log_clear
#   ::gec::configure -log
```

### output.tcl changes

Add injection logging in `type_async`:

```tcl
proc type_async {text} {
    variable worker_name

    if {$text eq ""} return

    # Log injection for feedback learning
    ::feedback::inject $text

    if {![::worker::exists $worker_name]} {
        puts stderr "Output thread not available, text dropped: $text"
        return
    }

    ::worker::send_async $worker_name [list ::output::worker::type_text $text]
}
```

### talkie.tcl changes

Initialize feedback module at startup:

```tcl
# After loading other modules
source [file join $script_dir feedback.tcl]
::feedback::init
```

## 3. Claude Code Hook

Create `~/.config/talkie/hooks/log-submission.sh`:

```bash
#!/bin/bash
# Log Claude Code prompt submissions to Talkie's unified feedback log

FEEDBACK_LOG="$HOME/.talkie/feedback.jsonl"

# Read JSON from stdin, transform to our format
jq -c '{
  ts: (now * 1000 | floor),
  type: "submit",
  text: .prompt,
  session_id: .session_id
}' >> "$FEEDBACK_LOG"
```

Configure in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "~/.config/talkie/hooks/log-submission.sh"
      }
    ]
  }
}
```

## 4. Unified Log Format

All events in `~/.config/talkie/feedback.jsonl`:

```jsonl
{"ts":1705500000000,"type":"gec","input":"their going","output":"they're going"}
{"ts":1705500000050,"type":"inject","text":"they're going"}
{"ts":1705500005000,"type":"submit","text":"they're going to the store","session_id":"abc123"}
{"ts":1705500010000,"type":"gec","input":"i think","output":"I think"}
{"ts":1705500010050,"type":"inject","text":"I think"}
{"ts":1705500015000,"type":"submit","text":"I think that's correct","session_id":"abc123"}
```

## 5. Correlation Analysis

Query the unified log to find corrections:

```bash
# Find all user edits (inject != submit within 30s window)
jq -s '
  [.[] | select(.type == "inject")] as $injects |
  [.[] | select(.type == "submit")] as $submits |
  [$injects[] as $i |
    ($submits[] | select(.ts > $i.ts and .ts < ($i.ts + 30000))) as $s |
    select($i.text != $s.text) |
    {injected: $i.text, submitted: $s.text, delay_ms: ($s.ts - $i.ts)}
  ]
' ~/.config/talkie/feedback.jsonl

# Find GEC corrections that user then modified
jq -s '
  [.[] | select(.type == "gec")] as $gecs |
  [.[] | select(.type == "submit")] as $submits |
  [$gecs[] as $g |
    ($submits[] | select(.ts > $g.ts and .ts < ($g.ts + 30000))) as $s |
    {gec_input: $g.input, gec_output: $g.output, user_final: $s.text}
  ]
' ~/.config/talkie/feedback.jsonl
```

## 6. Migration

Remove old GEC log after confirming unified logging works:

```bash
# Backup old log
mv ~/.talkie-gec.log ~/.talkie-gec.log.bak

# Or convert to new format
while IFS='|' read -r ts rest; do
  input=$(echo "$rest" | sed 's/.*"\(.*\)" -> .*/\1/')
  output=$(echo "$rest" | sed 's/.* -> "\(.*\)"/\1/')
  echo "{\"ts\":$(date -d "$ts" +%s)000,\"type\":\"gec\",\"input\":\"$input\",\"output\":\"$output\"}"
done < ~/.talkie-gec.log >> ~/.config/talkie/feedback.jsonl
```

## 7. Future Enhancements

1. **Confidence scores**: Include Vosk confidence in inject events
2. **Edit distance**: Pre-compute Levenshtein in correlation
3. **Session grouping**: Group by Claude session for context
4. **Real-time daemon**: Correlate on-the-fly, alert on patterns
5. **Model fine-tuning**: Feed corrections to custom LM training
