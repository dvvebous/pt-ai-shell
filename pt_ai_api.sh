#!/bin/sh

# Configuration
PT_AI_URL="${PT_AI_URL:-}"
PT_AI_API_VERSION="${PT_AI_API_VERSION:-}"
PT_AI_INITIAL_TOKEN="${PT_AI_INITIAL_TOKEN:-}"
PT_AI_INSECURE_SSL="${PT_AI_INSECURE_SSL:-false}"
PT_AI_TOKEN_FILE="${PT_AI_TOKEN_FILE:-.pt_ai_tokens.json}"

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

# Helper to load tokens from file
load_tokens() {
    if [ -f "$PT_AI_TOKEN_FILE" ]; then
        PT_AI_ACCESS_TOKEN=$(jq -r '.accessToken // empty' "$PT_AI_TOKEN_FILE")
        PT_AI_REFRESH_TOKEN=$(jq -r '.refreshToken // empty' "$PT_AI_TOKEN_FILE")
    fi
}

# Helper to save tokens to file
save_tokens() {
    jq -n \
        --arg at "$PT_AI_ACCESS_TOKEN" \
        --arg rt "$PT_AI_REFRESH_TOKEN" \
        '{accessToken: $at, refreshToken: $rt}' > "$PT_AI_TOKEN_FILE"
}

# Function to perform initial authentication
pt_ai_auth() {
    check_dependencies || return 1

    if [ -z "$PT_AI_URL" ]; then
        echo "Error: PT_AI_URL is not set." >&2
        return 1
    fi

    if [ -z "$PT_AI_INITIAL_TOKEN" ]; then
        echo "Error: PT_AI_INITIAL_TOKEN is not set." >&2
        return 1
    fi

    local curl_opts="$(get_curl_opts)"
    local url="${PT_AI_URL}/api${PT_AI_API_VERSION:+/${PT_AI_API_VERSION}}/auth/signin"

    echo "Authenticating with PT AI Enterprise Server at ${url}..." >&2

    local response
    # We use unquoted $curl_opts to expand into flags
    response=$(curl $curl_opts -X GET "$url" \
        -H "Access-Token: ${PT_AI_INITIAL_TOKEN}" \
        -H "Content-Type: application/json")

    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to PT AI server." >&2
        return 1
    fi

    local access_token
    access_token=$(echo "$response" | jq -r '.accessToken // empty')
    local refresh_token
    refresh_token=$(echo "$response" | jq -r '.refreshToken // empty')

    if [ -z "$access_token" ] || [ -z "$refresh_token" ]; then
        echo "Error: Failed to authenticate. Response: $response" >&2
        return 1
    fi

    PT_AI_ACCESS_TOKEN="$access_token"
    PT_AI_REFRESH_TOKEN="$refresh_token"
    save_tokens

    echo "Authentication successful." >&2
    return 0
}

# Function to refresh the access token
pt_ai_refresh_token() {
    check_dependencies || return 1

    load_tokens

    if [ -z "$PT_AI_REFRESH_TOKEN" ]; then
        echo "Error: No refresh token available. Please authenticate first." >&2
        return 1
    fi

    local curl_opts="$(get_curl_opts)"
    local url="${PT_AI_URL}/api${PT_AI_API_VERSION:+/${PT_AI_API_VERSION}}/auth/refreshToken"

    echo "Refreshing access token..." >&2

    local response
    response=$(curl $curl_opts -X GET "$url" \
        -H "Authorization: Bearer ${PT_AI_REFRESH_TOKEN}" \
        -H "Content-Type: application/json")

    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to PT AI server for token refresh." >&2
        return 1
    fi

    local access_token
    access_token=$(echo "$response" | jq -r '.accessToken // empty')
    local new_refresh_token
    new_refresh_token=$(echo "$response" | jq -r '.refreshToken // empty')

    if [ -z "$access_token" ]; then
        echo "Error: Failed to refresh token. Response: $response" >&2
        return 1
    fi

    PT_AI_ACCESS_TOKEN="$access_token"
    if [ -n "$new_refresh_token" ]; then
        PT_AI_REFRESH_TOKEN="$new_refresh_token"
    fi
    save_tokens

    echo "Token refresh successful." >&2
    return 0
}

# Function to parse Project ID from log file
pt_ai_parse_project_id_from_log() {
    local log_file="$1"
    if [ ! -f "$log_file" ]; then
        echo "Error: Log file '$log_file' not found." >&2
        return 1
    fi
    # Extract the first UUID found after /api/projects/
    # Use -a to treat binary as text, and sed to remove ANSI codes
    local project_id
    project_id=$(cat "$log_file" | sed 's/\x1b\[[0-9;]*m//g' | grep -a -oE '/api/projects/[0-9a-fA-F-]{36}' | head -n 1 | awk -F'/' '{print $4}')

    if [ -z "$project_id" ]; then
        echo "Debug: Could not find Project ID in log file using pattern '/api/projects/UUID'" >&2
    fi
    echo "$project_id"
}

# Function to perform an API request with auto-refresh logic
pt_ai_api_request() {
    check_dependencies || return 1

    load_tokens

    if [ -z "$PT_AI_ACCESS_TOKEN" ]; then
        echo "Error: Not authenticated. Call pt_ai_auth first." >&2
        return 1
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
        -H "Authorization: Bearer ${PT_AI_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -D "$header_dump" \
        "$@")

    http_code=$(awk 'NR==1{print $2}' "$header_dump")
    rm -f "$header_dump"

    if [ "$http_code" = "401" ]; then
        echo "Received 401 Unauthorized. Attempting to refresh token..." >&2
        if pt_ai_refresh_token; then
            echo "Retrying request with new token..." >&2
            load_tokens # Reload tokens after refresh

            header_dump=$(mktemp)
            response_body=$(curl $curl_opts -X "$method" "$url" \
                -H "Authorization: Bearer ${PT_AI_ACCESS_TOKEN}" \
                -H "Content-Type: application/json" \
                -D "$header_dump" \
                "$@")
            http_code=$(awk 'NR==1{print $2}' "$header_dump")
            rm -f "$header_dump"
        else
            echo "Error: Token refresh failed. Aborting request." >&2
            return 1
        fi
    fi

    echo "$response_body"

    if echo "$http_code" | grep -q "^2"; then
        return 0
    else
        echo "API Request failed with HTTP $http_code" >&2
        return 1
    fi
}

# Function to perform an API request and download the response to a file
pt_ai_api_download() {
    check_dependencies || return 1

    load_tokens

    if [ -z "$PT_AI_ACCESS_TOKEN" ]; then
        echo "Error: Not authenticated. Call pt_ai_auth first." >&2
        return 1
    fi

    local method="$1"
    local endpoint="$2"
    local output_file="$3"
    shift 3

    local curl_opts="$(get_curl_opts)"
    local url="${PT_AI_URL}/api${PT_AI_API_VERSION:+/${PT_AI_API_VERSION}}${endpoint}"

    local header_dump
    header_dump=$(mktemp)
    local http_code

    echo "Downloading from $url to $output_file..." >&2

    curl $curl_opts -X "$method" "$url" \
        -H "Authorization: Bearer ${PT_AI_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -D "$header_dump" \
        -o "$output_file" \
        "$@"

    http_code=$(awk 'NR==1{print $2}' "$header_dump")
    rm -f "$header_dump"

    if [ "$http_code" = "401" ]; then
        echo "Received 401 Unauthorized. Attempting to refresh token..." >&2
        if pt_ai_refresh_token; then
            echo "Retrying request with new token..." >&2
            load_tokens # Reload tokens after refresh

             header_dump=$(mktemp)
             curl $curl_opts -X "$method" "$url" \
                -H "Authorization: Bearer ${PT_AI_ACCESS_TOKEN}" \
                -H "Content-Type: application/json" \
                -D "$header_dump" \
                -o "$output_file" \
                "$@"
            http_code=$(awk 'NR==1{print $2}' "$header_dump")
            rm -f "$header_dump"
        else
             echo "Error: Token refresh failed. Aborting request." >&2
             return 1
        fi
    fi

    if echo "$http_code" | grep -q "^2"; then
        echo "Download successful." >&2
        return 0
    else
        echo "API Request failed with HTTP $http_code" >&2
        # Start of file content might be error message
        head -n 5 "$output_file" >&2
        return 1
    fi
}

# Function to get branch ID by name
pt_ai_get_branch_id_by_name() {
    local project_id="$1"
    local branch_name="$2"

    if [ -z "$project_id" ] || [ -z "$branch_name" ]; then
        echo "Error: Project ID and Branch Name are required." >&2
        return 1
    fi

    local response
    response=$(pt_ai_api_request "GET" "/projects/${project_id}/branches")

    if [ $? -ne 0 ]; then
        return 1
    fi

    echo "$response" | jq -r --arg name "$branch_name" '.[] | select(.name == $name) | .id'
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

# Function to get last scan result ID for a branch
pt_ai_get_last_scan_result_id() {
    local branch_id="$1"

    if [ -z "$branch_id" ]; then
        echo "Error: Branch ID is required." >&2
        return 1
    fi

    local response
    response=$(pt_ai_api_request "GET" "/branches/${branch_id}/scanResults/last")

    if [ $? -ne 0 ]; then
        return 1
    fi

    echo "$response" | jq -r '.id'
}

# Function to get report template ID by type/name
pt_ai_get_template_id_by_name() {
    local template_name="$1" # e.g. PlainReport, Sarif
    local locale_id="${2:-en}" # Default to en if not specified

    if [ -z "$template_name" ]; then
        echo "Error: Template name is required." >&2
        return 1
    fi

    # Try fetching by type first
    local response
    response=$(pt_ai_api_request "GET" "/reports/templates/${template_name}?localeId=${locale_id}")

    if [ $? -eq 0 ]; then
         local id
         id=$(echo "$response" | jq -r '.id // empty')
         if [ -n "$id" ]; then
             echo "$id"
             return 0
         fi
         # If ID is empty but response code 200, maybe response is invalid JSON or empty object
         echo "Debug: Response for template '${template_name}' was not valid JSON or missing ID: $response" >&2
    fi

    # Fallback: List all templates and find by name/type
    echo "Debug: Direct fetch failed. Listing all templates..." >&2
    response=$(pt_ai_api_request "GET" "/reports/templates?localeId=${locale_id}")

    if [ $? -eq 0 ]; then
        local id
        # Look for a template where name or type matches the requested name
        id=$(echo "$response" | jq -r --arg name "$template_name" '.[] | select(.name == $name or .type == $name) | .id' | head -n 1)
        if [ -n "$id" ]; then
            echo "$id"
            return 0
        fi
    fi

    echo "Error: Could not find template ID for '${template_name}'." >&2
    echo "Debug: Last API response: $response" >&2
    return 1
}

# Function to generate report
pt_ai_generate_report() {
    local project_id="$1"
    local scan_result_id="$2"
    local template_name="$3"
    local output_file="$4"
    local locale_id="${5:-en}" # Default locale en

    if [ -z "$project_id" ] || [ -z "$scan_result_id" ] || [ -z "$template_name" ] || [ -z "$output_file" ]; then
        echo "Error: Project ID, Scan Result ID, Template Name, and Output File are required." >&2
        return 1
    fi

    local template_id
    template_id=$(pt_ai_get_template_id_by_name "$template_name")
    if [ -z "$template_id" ]; then
         echo "Error: Could not find template ID for '$template_name'." >&2
         return 1
    fi

    # Generate random session ID (UUID)
    local session_id
    if command -v uuidgen > /dev/null 2>&1; then
        session_id=$(uuidgen)
    else
        # Fallback UUID generation
        session_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")
    fi

    # Construct JSON body
    local json_body
    json_body=$(jq -n \
        --arg pid "$project_id" \
        --arg sid "$scan_result_id" \
        --arg tid "$template_id" \
        --arg sess "$session_id" \
        --arg loc "$locale_id" \
        '{
            projectId: $pid,
            scanResultId: $sid,
            sessionId: $sess,
            localeId: $loc,
            parameters: {
                reportTemplateId: $tid,
                useFilters: false
            }
        }')

    echo "Generating report '$template_name' to '$output_file'..." >&2
    pt_ai_api_download "POST" "/reports/generate" "$output_file" -d "$json_body"
}

# Function to automate report generation based on logs
pt_ai_automate_process() {
    local log_file="$1"
    local branch_name="$2"
    local report_types="$3" # Comma separated list, e.g. "PlainReport,Sarif"

    if [ -z "$log_file" ] || [ -z "$branch_name" ]; then
        echo "Usage: pt_ai_automate_process <log_file> <branch_name> [report_types]" >&2
        return 1
    fi

    # 1. Parse Project ID
    local project_id
    project_id=$(pt_ai_parse_project_id_from_log "$log_file")
    if [ -z "$project_id" ]; then
        echo "Error: Could not extract Project ID from log file." >&2
        return 1
    fi
    echo "Found Project ID: $project_id" >&2

    # 2. Get Branch ID
    local branch_id
    branch_id=$(pt_ai_get_branch_id_by_name "$project_id" "$branch_name")
    if [ -z "$branch_id" ]; then
        echo "Error: Could not find branch ID for branch '$branch_name'." >&2
        return 1
    fi
    echo "Found Branch ID: $branch_id" >&2

    # 3. Set Working Branch
    if ! pt_ai_set_working_branch "$branch_id"; then
         echo "Warning: Failed to set working branch." >&2
    fi

    # 4. Get Last Scan Result ID
    local scan_result_id
    scan_result_id=$(pt_ai_get_last_scan_result_id "$branch_id")
    if [ -z "$scan_result_id" ]; then
        echo "Error: Could not find last scan result ID." >&2
        return 1
    fi
    echo "Found Last Scan Result ID: $scan_result_id" >&2

    # 5. Generate Reports
    if [ -n "$report_types" ]; then
        echo "$report_types" | tr ',' '\n' | while read -r template; do
            # Trim whitespace
            template=$(echo "$template" | xargs)
            if [ -n "$template" ]; then
                 local output_file="${template}.report"
                 # Adjust extension based on template
                 if [ "$template" = "Sarif" ]; then output_file="${template}.json"; fi
                 if [ "$template" = "PlainReport" ]; then output_file="${template}.html"; fi

                 pt_ai_generate_report "$project_id" "$scan_result_id" "$template" "$output_file"
            fi
        done
    fi
}
