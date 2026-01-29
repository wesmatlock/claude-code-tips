#!/usr/bin/env bash
#
# half-clone-conversation.sh - Clone the later half of a Claude Code conversation
#
# Pure bash implementation - no Python/Node dependencies.
# Works on macOS (bash 3.2+) and Linux.
#
# Usage:
#   half-clone-conversation.sh <session-id> [project-path]
#
# Arguments:
#   session-id    The UUID of the conversation to clone (required)
#   project-path  The project path (default: current directory)
#
# Example:
#   half-clone-conversation.sh d96c899d-7501-4e81-a31b-e0095bb3b501
#   half-clone-conversation.sh d96c899d-7501-4e81-a31b-e0095bb3b501 /home/user/myproject
#
# After cloning, use 'claude -r' to see both the original and half-cloned conversation.
#

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
PROJECTS_DIR="${CLAUDE_DIR}/projects"
HISTORY_FILE="${CLAUDE_DIR}/history.jsonl"
TODOS_DIR="${CLAUDE_DIR}/todos"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    echo "Usage: $0 <session-id> [project-path]"
    echo ""
    echo "Arguments:"
    echo "  session-id    The UUID of the conversation to clone (required)"
    echo "  project-path  The project path (default: current directory)"
    exit 1
}

# UUID generation - works on both Mac and Linux
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback using $RANDOM
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' \
            $((RANDOM)) $((RANDOM)) $((RANDOM)) \
            $((RANDOM & 0x0fff | 0x4000)) \
            $((RANDOM & 0x3fff | 0x8000)) \
            $((RANDOM)) $((RANDOM)) $((RANDOM))
    fi
}

convert_path_to_dirname() {
    echo "$1" | sed 's|^/||' | sed 's|/|-|g' | sed 's|^|-|'
}

find_conversation_file() {
    local session_id="$1"
    local project_path="$2"
    local project_dirname
    project_dirname=$(convert_path_to_dirname "$project_path")
    local project_dir="${PROJECTS_DIR}/${project_dirname}"
    local conv_file="${project_dir}/${session_id}.jsonl"

    if [ -f "$conv_file" ]; then
        echo "$conv_file"
        return 0
    fi

    # Try to find in any project directory
    local found_file
    found_file=$(find "$PROJECTS_DIR" -name "${session_id}.jsonl" 2>/dev/null | head -1)

    if [ -n "$found_file" ]; then
        echo "$found_file"
        return 0
    fi

    return 1
}

get_project_from_conv_file() {
    local conv_file="$1"
    local project_dirname
    project_dirname=$(dirname "$conv_file" | xargs basename)
    echo "$project_dirname" | sed 's|^-|/|' | sed 's|-|/|g'
}

# Pre-generate UUIDs for the awk script
# We need enough UUIDs for all unique uuid/parentUuid/messageId values
pre_generate_uuids() {
    local count="$1"
    local output_file="$2"
    for ((i=0; i<count; i++)); do
        generate_uuid
    done > "$output_file"
}

half_clone_conversation() {
    local source_session="$1"
    local project_path="$2"

    # Generate timestamp for clone tag (e.g., "Jan 7 14:30")
    local clone_timestamp
    clone_timestamp=$(date "+%b %-d %H:%M")
    local clone_tag="[HALF-CLONE ${clone_timestamp}]"

    # Find source file
    local source_file
    if ! source_file=$(find_conversation_file "$source_session" "$project_path"); then
        log_error "Could not find conversation file for session: $source_session"
        log_info "Looking in: ${PROJECTS_DIR}"
        log_info "Available conversations:"
        find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null | while read -r f; do
            local fname
            fname=$(basename "$f")
            if [[ ${#fname} -eq 42 && "$fname" =~ ^[a-f0-9-]+\.jsonl$ ]]; then
                echo "  - ${fname%.jsonl}"
            fi
        done
        exit 1
    fi

    log_info "Found source conversation: $source_file"

    if [ -z "$project_path" ]; then
        project_path=$(get_project_from_conv_file "$source_file")
    fi

    # Count "clean" user messages (not tool_results - those require a preceding tool_use)
    # A clean user message is one where we can start a conversation
    local total_clean_user_messages
    total_clean_user_messages=$(grep '"type":"user"' "$source_file" | grep -cv '"type":"tool_result"' || echo "0")
    log_info "Total clean user messages in conversation: $total_clean_user_messages"

    if [ "$total_clean_user_messages" -lt 2 ]; then
        log_error "Conversation has fewer than 2 clean user messages, nothing to half-clone"
        exit 1
    fi

    # Calculate which clean user message to start from (halfway point)
    local skip_clean_count
    skip_clean_count=$((total_clean_user_messages / 2))
    local keep_clean_count
    keep_clean_count=$((total_clean_user_messages - skip_clean_count))

    # OPTIMIZED: Find the line number where the target clean user message starts
    # Use grep -n to get all clean user message line numbers in one pass
    local clean_user_line_numbers
    clean_user_line_numbers=$(grep -n '"type":"user"' "$source_file" | grep -v '"type":"tool_result"' | cut -d: -f1)

    # Get the line number of the (skip_clean_count + 1)th clean user message
    local skip_count
    skip_count=$(echo "$clean_user_line_numbers" | sed -n "$((skip_clean_count + 1))p")
    # We want to skip lines BEFORE this one, so subtract 1
    skip_count=$((skip_count - 1))

    log_info "Skipping first $skip_clean_count clean user messages ($skip_count lines), keeping $keep_clean_count clean user messages"

    # Generate new session ID
    local new_session
    new_session=$(generate_uuid)
    log_info "Generated new session ID: $new_session"

    # Target file
    local project_dirname
    project_dirname=$(convert_path_to_dirname "$project_path")
    local project_dir="${PROJECTS_DIR}/${project_dirname}"
    local target_file="${project_dir}/${new_session}.jsonl"

    mkdir -p "$project_dir"
    log_info "Half-cloning conversation to: $target_file"

    # OPTIMIZED First pass: find if last clean user message is a clone/half-clone command
    # Use grep -n to find all user messages in a single pass, then filter
    local stop_at_line=0
    local last_clone_cmd_line=0
    local last_clean_user_line=0

    # Get all user message lines with line numbers (much faster than per-line grep)
    # Filter to clean user messages (not tool_result, not isMeta)
    local clean_user_lines
    clean_user_lines=$(grep -n '"type":"user"' "$source_file" | grep -v '"type":"tool_result"' | grep -v '"isMeta":true' || true)

    if [ -n "$clean_user_lines" ]; then
        # Get the last clean user message line
        local last_line_info
        last_line_info=$(echo "$clean_user_lines" | tail -1)
        last_clean_user_line=$(echo "$last_line_info" | cut -d: -f1)

        # Check if it's a clone command
        if echo "$last_line_info" | grep -qE '<command-message>(dx:)?clone</command-message>|<command-message>(dx:)?half-clone</command-message>' 2>/dev/null; then
            last_clone_cmd_line=$last_clean_user_line
        fi
    fi

    # If the last clean user message is a clone command, stop before it
    if [ "$last_clone_cmd_line" -gt 0 ] && [ "$last_clone_cmd_line" -eq "$last_clean_user_line" ]; then
        stop_at_line=$last_clone_cmd_line
        log_info "Will exclude /clone command and subsequent messages (line $stop_at_line onwards)"
    fi

    # Pre-generate UUIDs for awk (estimate: 3 per line for uuid, parentUuid, messageId)
    local lines_to_process=$(($(wc -l < "$source_file") - skip_count))
    local uuid_count=$((lines_to_process * 3 + 100))  # Extra buffer
    local uuid_file
    uuid_file=$(mktemp)
    trap "rm -f '$uuid_file'" EXIT
    log_info "Pre-generating UUIDs..."
    pre_generate_uuids "$uuid_count" "$uuid_file"

    # Process with awk - single pass, no external commands per line
    log_info "Processing with awk..."
    awk -v skip_count="$skip_count" \
         -v stop_at_line="$stop_at_line" \
         -v new_session="$new_session" \
         -v clone_tag="$clone_tag" \
         -v uuid_file="$uuid_file" '
    BEGIN {
        first_message = 1
        first_user = 1
        output_count = 0
        uuid_idx = 0
        # Load pre-generated UUIDs
        while ((getline uuid < uuid_file) > 0) {
            uuids[uuid_idx++] = uuid
        }
        close(uuid_file)
        next_uuid = 0
    }

    function get_new_uuid(old_uuid) {
        if (old_uuid in uuid_map) {
            return uuid_map[old_uuid]
        }
        new_uuid = uuids[next_uuid++]
        uuid_map[old_uuid] = new_uuid
        return new_uuid
    }

    function extract_uuid(line, key,    pattern, match_str, uuid) {
        pattern = "\"" key "\":\"[a-f0-9-]{36}\""
        if (match(line, pattern)) {
            match_str = substr(line, RSTART, RLENGTH)
            # Extract just the UUID value
            uuid = match_str
            gsub("\"" key "\":\"", "", uuid)
            gsub("\"", "", uuid)
            return uuid
        }
        return ""
    }

    function halve_number(line, field,    pattern, num, halved) {
        pattern = "\"" field "\":[0-9]+"
        if (match(line, pattern)) {
            match_str = substr(line, RSTART, RLENGTH)
            gsub("\"" field "\":", "", match_str)
            num = int(match_str)
            halved = int(num / 2)
            gsub("\"" field "\":" num, "\"" field "\":" halved, line)
        }
        return line
    }

    NR <= skip_count { next }
    stop_at_line > 0 && NR >= stop_at_line { exit }
    /^$/ { next }

    {
        line = $0

        # Replace sessionId
        old_session = extract_uuid(line, "sessionId")
        if (old_session != "") {
            gsub("\"sessionId\":\"" old_session "\"", "\"sessionId\":\"" new_session "\"", line)
        }

        # Replace uuid (not parentUuid, not sessionId) - look for standalone "uuid"
        if (match(line, /"uuid":"[a-f0-9-]{36}"/)) {
            match_str = substr(line, RSTART, RLENGTH)
            old_uuid = match_str
            gsub("\"uuid\":\"", "", old_uuid)
            gsub("\"", "", old_uuid)
            new_uuid = get_new_uuid(old_uuid)
            gsub("\"uuid\":\"" old_uuid "\"", "\"uuid\":\"" new_uuid "\"", line)
        }

        # Handle parentUuid
        if (first_message) {
            # Nullify parentUuid for first message
            gsub(/"parentUuid":"[a-f0-9-]*"/, "\"parentUuid\":null", line)
            first_message = 0
        } else {
            old_parent = extract_uuid(line, "parentUuid")
            if (old_parent != "") {
                new_parent = get_new_uuid(old_parent)
                gsub("\"parentUuid\":\"" old_parent "\"", "\"parentUuid\":\"" new_parent "\"", line)
            }
        }

        # Replace messageId
        old_msgid = extract_uuid(line, "messageId")
        if (old_msgid != "") {
            new_msgid = get_new_uuid(old_msgid)
            gsub("\"messageId\":\"" old_msgid "\"", "\"messageId\":\"" new_msgid "\"", line)
        }

        # Tag first user message
        if (first_user && index(line, "\"type\":\"user\"") > 0) {
            gsub("\"content\":\"", "\"content\":\"" clone_tag " ", line)
            gsub("\"text\":\"", "\"text\":\"" clone_tag " ", line)
            first_user = 0
        }

        # Halve token counts
        line = halve_number(line, "input_tokens")
        line = halve_number(line, "cache_read_input_tokens")
        line = halve_number(line, "cache_creation_input_tokens")

        print line
    }
    ' "$source_file" > "$target_file"

    local output_line_count
    output_line_count=$(wc -l < "$target_file" | tr -d ' ')
    log_success "Wrote $output_line_count messages to $target_file"

    # Update history.jsonl
    log_info "Updating history file..."

    # Get display text from first user message in the KEPT portion
    local display_text
    display_text=$(tail -n +"$((skip_count + 1))" "$source_file" | grep '"type":"user"' | head -1 | \
        grep -oE '"content":"[^"]*"' | head -1 | \
        sed 's/"content":"//;s/"$//' | \
        head -c 200 || echo "[Half-cloned conversation]")

    if [ -z "$display_text" ]; then
        # Try array format
        display_text=$(tail -n +"$((skip_count + 1))" "$source_file" | grep '"type":"user"' | head -1 | \
            grep -oE '"text":"[^"]*"' | head -1 | \
            sed 's/"text":"//;s/"$//' | \
            head -c 200 || echo "[Half-cloned conversation]")
    fi

    display_text="${clone_tag} ${display_text}"

    # Timestamp (milliseconds)
    local timestamp
    if [[ "$OSTYPE" == "darwin"* ]]; then
        timestamp=$(( $(date +%s) * 1000 + 1000 ))
    else
        timestamp=$(( $(date +%s%3N) + 1000 ))
    fi

    # Escape for JSON
    display_text=$(echo "$display_text" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')

    # Add history entry
    echo "{\"display\":\"${display_text}\",\"pastedContents\":{},\"timestamp\":${timestamp},\"project\":\"${project_path}\",\"sessionId\":\"${new_session}\"}" >> "$HISTORY_FILE"
    log_success "History entry added"

    # Note: We don't copy todos for half-clone since the context is truncated

    log_success "Conversation half-cloned successfully!"
    echo ""
    echo "Original session: $source_session"
    echo "New session:      $new_session"
    echo "Project:          $project_path"
    echo "Clean user msgs:  $keep_clean_count of $total_clean_user_messages (skipped first $skip_clean_count)"
    echo ""
    echo "To resume the half-cloned conversation, use:"
    echo "  claude -r"
    echo ""
    echo "Then select the conversation marked with ${clone_tag}"
}

# Main
if [ $# -lt 1 ]; then
    usage
fi

SESSION_ID="$1"
PROJECT_PATH="${2:-$(pwd)}"

# Validate session ID
if ! [[ "$SESSION_ID" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
    log_error "Invalid session ID format. Expected UUID like: d96c899d-7501-4e81-a31b-e0095bb3b501"
    exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
    log_error "Claude directory not found at $CLAUDE_DIR"
    exit 1
fi

half_clone_conversation "$SESSION_ID" "$PROJECT_PATH"
