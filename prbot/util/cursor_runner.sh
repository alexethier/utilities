#!/bin/bash
# Cursor utility functions for prbot
# This file is sourced by handler scripts that need to run cursor

# Model configuration
CURSOR_MODEL_DEFAULT="sonnet-4.5"
CURSOR_MODEL_THINKING="opus-4.5-thinking"

# Run cursor with prompt and optional improved thinking
# Usage: run_cursor <prompt> [use_thinking]
# Args:
#   prompt       - The prompt to send to cursor
#   use_thinking - Optional boolean (true/false). If true, uses opus model. Default: false
run_cursor() {
    local prompt="$1"
    local use_thinking="${2:-false}"
    
    local model="$CURSOR_MODEL_DEFAULT"
    if [ "$use_thinking" = "true" ]; then
        model="$CURSOR_MODEL_THINKING"
    fi
    
    cursor -p "$prompt" -m "$model"
}

# Run cursor in a completely isolated process
# Usage: run_cursor_isolated "prompt" [use_thinking]
# Args:
#   prompt       - The prompt to send to cursor
#   use_thinking - Optional boolean (true/false). If true, uses opus model. Default: false
run_cursor_isolated() {
    local prompt="$1"
    local use_thinking="${2:-false}"
    
    # Select model based on thinking flag
    local model="$CURSOR_MODEL_DEFAULT"
    if [ "$use_thinking" = "true" ]; then
        model="$CURSOR_MODEL_THINKING"
    fi
    
    # Resolve full path to cursor executable
    local cursor_path=$(which cursor)
    if [ -z "$cursor_path" ]; then
        echo "❌ Error: cursor executable not found in PATH"
        return 1
    fi
    
    # Create isolated runner in a temp directory
    local runner_id="$$_$(date +%s)"
    local runner_dir="/tmp/cursor_runner_${runner_id}"
    mkdir -p "$runner_dir"
    
    local runner_script="$runner_dir/run.sh"
    local pid_file="$runner_dir/pid"
    local exit_file="$runner_dir/exit"
    local log_file="$runner_dir/log"
    
    echo "📜 Runner dir: $runner_dir"
    echo "🤖 Model: $model"
    
    cat > "$runner_script" <<RUNNER_EOF
#!/usr/bin/env bash --norc --noprofile
$cursor_path -p "$prompt" -m "$model" | tee "$log_file" 2>&1
echo \$? > "$exit_file"
RUNNER_EOF
    chmod +x "$runner_script"

    # Launch in completely fresh context (macOS compatible):
    # - env -i: clear ALL inherited environment variables
    # - Only pass essential vars: PATH, HOME, USER, TMPDIR
    # - Subshell (...) to isolate further
    (
        env -i \
            PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/bin" \
            HOME="$HOME" \
            USER="$USER" \
            TMPDIR="${TMPDIR:-/tmp}" \
            /bin/bash --norc --noprofile "$runner_script"
    ) </dev/null >/dev/null 2>&1 &
    local runner_pid=$!
    echo "$runner_pid" > "$pid_file"
    
    echo "🚀 Launched isolated cursor process (PID: $runner_pid)"
    
    # Tail the log file in the background
    touch "$log_file"
    tail -F "$log_file" &
    local tail_pid=$!
    
    # Wait for process to finish by polling PID
    while kill -0 "$runner_pid" 2>/dev/null; do
        sleep 1
    done
    
    # Stop the tail process (ignore exit code 143 from SIGTERM)
    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    
    # Check exit status
    if [ -f "$exit_file" ]; then
        local exit_code=$(cat "$exit_file")
        echo "✅ Cursor process finished (exit code: $exit_code)"
        return "$exit_code"
    else
        echo "⚠️  Cursor process finished (no exit code captured)"
        return 1
    fi
}

