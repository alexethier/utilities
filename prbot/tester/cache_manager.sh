#!/bin/bash
# Build Cache Manager - CRUD operations for build state cache
# Cache file: $PRBOT_WORKDIR/.prbot_build_cache.csv
#
# CSV Schema:
#   commit_id,state,timestamp
#
# States: passed, fail
# timestamp: Unix epoch time

# Get the cache file path
_cache_file() {
    echo "$PRBOT_WORKDIR/.prbot_build_cache.csv"
}

# CSV header
_cache_header() {
    echo "commit_id,state,timestamp"
}

# ============================================================================
# Utility
# ============================================================================

# Initialize cache file with header if it doesn't exist
# Usage: cache_init
cache_init() {
    local cache_file=$(_cache_file)
    if [ ! -f "$cache_file" ]; then
        _cache_header > "$cache_file"
    fi
}

# Clean up old entries if cache exceeds max size
# If 300+ entries, delete oldest until only 200 remain
_cache_cleanup() {
    local cache_file=$(_cache_file)
    local max_entries=300
    local target_entries=200
    
    if [ ! -f "$cache_file" ]; then
        return
    fi
    
    # Count entries (subtract 1 for header)
    local count=$(($(wc -l < "$cache_file") - 1))
    
    if [ "$count" -lt "$max_entries" ]; then
        return
    fi
    
    # Sort by timestamp (field 3), keep header + newest entries
    local tmp_file="${cache_file}.tmp"
    head -1 "$cache_file" > "$tmp_file"
    tail -n +2 "$cache_file" | sort -t',' -k3 -n -r | head -n "$target_entries" >> "$tmp_file"
    mv "$tmp_file" "$cache_file"
}

# ============================================================================
# Create
# ============================================================================

# Add new entry to cache
# Usage: cache_create <commit_id> <state>
cache_create() {
    local commit_id=$1
    local state=$2
    local timestamp=$(date +%s)
    
    cache_init
    
    local cache_file=$(_cache_file)
    echo "$commit_id,$state,$timestamp" >> "$cache_file"
    
    _cache_cleanup
}

# ============================================================================
# Read
# ============================================================================

# Check if entry exists for commit
# Usage: cache_exists <commit_id>
# Returns: 0 if exists, 1 otherwise
cache_exists() {
    local commit_id=$1
    local cache_file=$(_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    grep -q "^$commit_id," "$cache_file"
}

# Get full CSV row for commit
# Usage: cache_read <commit_id>
# Returns: Full CSV row or empty if not found
cache_read() {
    local commit_id=$1
    local cache_file=$(_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return
    fi
    
    grep "^$commit_id," "$cache_file"
}

# Get state for commit
# Usage: cache_get_state <commit_id>
# Returns: state (passed/fail) or empty if not found
cache_get_state() {
    local commit_id=$1
    local row=$(cache_read "$commit_id")
    
    if [ -n "$row" ]; then
        echo "$row" | cut -d',' -f2
    fi
}

# ============================================================================
# Update
# ============================================================================

# Update existing entry
# Usage: cache_update <commit_id> <state>
cache_update() {
    local commit_id=$1
    local state=$2
    
    local cache_file=$(_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    if ! cache_exists "$commit_id"; then
        return 1
    fi
    
    # Remove old entry and add updated one
    cache_delete "$commit_id"
    cache_create "$commit_id" "$state"
}

# ============================================================================
# Delete
# ============================================================================

# Remove entry for commit
# Usage: cache_delete <commit_id>
cache_delete() {
    local commit_id=$1
    local cache_file=$(_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return
    fi
    
    # Create temp file, filter out the commit, replace original
    local tmp_file="${cache_file}.tmp"
    grep -v "^$commit_id," "$cache_file" > "$tmp_file"
    mv "$tmp_file" "$cache_file"
}
