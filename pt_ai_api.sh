#!/bin/sh

# Configuration
PT_AI_URL="${AISA_HOST:-}"
PT_AI_API_VERSION="${PT_AI_API_VERSION:-}"
PT_AI_API_TOKEN="${AISA_TOKEN:-}"
PT_AI_INSECURE_SSL="${PT_AI_INSECURE_SSL:-false}"
PT_AI_JWT=""

# Helper function to check dependencies
check_dependencies() {
    if ! command -v jq > /dev/null 2>&1; then
        echo "Error: jq is required but not installed." >&2
        return 1
    fi
    if ! command -v curl > /dev/null 2>&1; then
        echo "Error: curl is required but not installed." >&2
        return 1
    fi
}

# Helper function to get curl options
get_curl_opts() {
    if [ "$PT_AI_INSECURE_SSL" = "true" ]; then
        echo "-s -S -k"
    else
        echo "-s -S"
    fi
}

# Function to parse Branch ID from log file
pt_ai_parse_branch_id_from_log() {
    local log_file="$1"
    if [ ! -f "$log_file" ]; then
        echo "Error: Log file '$log_file' not found." >&2
        return 1
    fi
    # Extract the UUID found after "branch id: "
    # Use -a to treat binary as text, and sed to remove ANSI codes
    local branch_id
    branch_id=$(cat "$log_file" | sed 's/\x1b\[[0-9;]*m//g' | grep -a -oE 'branch id: [0-9a-fA-F-]{36}' | head -n 1 | awk -F': ' '{print $2}')

    if [ -z "$branch_id" ]; then
        echo "Debug: Could not find Branch ID in log file using pattern 'branch id: UUID'" >&2
    fi
    echo "$branch_id"
}

# Function to authenticate and get JWT
pt_ai_auth() {
    check_dependencies || return 1

    if [ -z "$PT_AI_URL" ]; then
        echo "Error: AISA_HOST is not set." >&2
        return 1
    fi

    if [ -z "$PT_AI_API_TOKEN" ]; then
        echo "Error: AISA_TOKEN is not set." >&2
        return 1
    fi

    local curl_opts="$(get_curl_opts)"
    local url="${PT_AI_URL}/api${PT_AI_API_VERSION:+/${PT_AI_API_VERSION}}/auth/signin"

    # Authenticate using the API token to get a session JWT
    local response
    response=$(curl $curl_opts -X GET "$url" \
        -H "Access-Token: ${PT_AI_API_TOKEN}" \
        -H "Content-Type: application/json")

    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to PT AI server for authentication." >&2
        return 1
    fi

    local access_token
    access_token=$(echo "$response" | jq -r '.accessToken // empty')

    if [ -z "$access_token" ]; then
        echo "Error: Failed to authenticate. Check AISA_TOKEN." >&2
        # echo "Response: $response" >&2
        return 1
    fi

    PT_AI_JWT="$access_token"
    echo "Authentication successful." >&2
}

# Function to perform an API request
pt_ai_api_request() {
    check_dependencies || return 1

    if [ -z "$PT_AI_JWT" ]; then
        # Try to authenticate if JWT is missing
        pt_ai_auth
        if [ -z "$PT_AI_JWT" ]; then
             echo "Error: Not authenticated." >&2
             return 1
        fi
    fi

    local method="$1"
    local endpoint="$2"
    shift 2

    local curl_opts="$(get_curl_opts)"
    local url="${PT_AI_URL}/api${PT_AI_API_VERSION:+/${PT_AI_API_VERSION}}${endpoint}"

    local header_dump
    header_dump=$(mktemp)

    local response_body
    local http_code

    response_body=$(curl $curl_opts -X "$method" "$url" \
        -H "Authorization: Bearer ${PT_AI_JWT}" \
        -H "Content-Type: application/json" \
        -D "$header_dump" \
        "$@")

    http_code=$(awk 'NR==1{print $2}' "$header_dump")
    rm -f "$header_dump"

    echo "$response_body"

    if echo "$http_code" | grep -q "^2"; then
        return 0
    else
        echo "API Request failed with HTTP $http_code" >&2
        return 1
    fi
}

# Function to set working branch
pt_ai_set_working_branch() {
    local branch_id="$1"

    if [ -z "$branch_id" ]; then
        echo "Error: Branch ID is required." >&2
        return 1
    fi

    echo "Setting working branch to ${branch_id}..." >&2
    local response
    response=$(pt_ai_api_request "POST" "/branches/${branch_id}/setWorking")

    if [ $? -ne 0 ]; then
        echo "Error: Failed to set working branch." >&2
        return 1
    fi
    echo "Working branch set successfully." >&2
}

# Function to automate process based on logs
pt_ai_automate_process() {
    local log_file="$1"

    if [ -z "$log_file" ]; then
        echo "Usage: pt_ai_automate_process <log_file>" >&2
        return 1
    fi

    # 1. Parse Branch ID directly from log
    local branch_id
    branch_id=$(pt_ai_parse_branch_id_from_log "$log_file")

    if [ -z "$branch_id" ]; then
        echo "Error: Branch ID not found in logs." >&2
        return 1
    fi

    echo "Found Branch ID: $branch_id" >&2

    # 2. Set Working Branch
    if ! pt_ai_set_working_branch "$branch_id"; then
         echo "Warning: Failed to set working branch." >&2
    fi
}
