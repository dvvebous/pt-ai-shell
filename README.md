# PT AI Enterprise Server API Integration for CI/CD

This repository contains a Bash script to facilitate integration with PT AI Enterprise Server API in CI/CD pipelines (e.g., GitLab CI).

## Features

- **Authentication**: Handles initial authentication using `PT_AI_INITIAL_TOKEN`.
- **Token Management**: Stores access and refresh tokens in a local JSON file (`.pt_ai_tokens.json` by default).
- **Automatic Token Refresh**: Automatically detects HTTP 401 Unauthorized responses and refreshes the access token using the refresh token, then retries the request transparently.
- **Insecure SSL Support**: Optional support for self-signed certificates via `PT_AI_INSECURE_SSL`.
- **Report Generation**: Automatically generates and downloads reports (PlainReport, Sarif) for the last scan.
- **Branch Management**: Sets the default/working branch automatically.
- **Log Parsing**: Parses execution logs (e.g., from `aisa` tool) to automatically identify the project and branch for subsequent API actions.

## Prerequisites

- `bash`
- `curl`
- `jq`
- `uuidgen` (optional, for generating session IDs for reports)

## Usage

### 1. Configuration

Set the following environment variables in your CI/CD settings or script:

| Variable | Description | Default |
|----------|-------------|---------|
| `PT_AI_URL` | Base URL of PT AI Enterprise Server (e.g., `https://pt-ai.example.com`) | Required |
| `PT_AI_INITIAL_TOKEN` | Initial access token provided by PT AI | Required |
| `PT_AI_API_VERSION` | API version number (e.g., `2`). Set to empty string if version is not in the URL path. | `2` (or empty if updated) |
| `PT_AI_INSECURE_SSL` | Set to `true` to skip SSL verification (e.g., for self-signed certs) | `false` |
| `PT_AI_TOKEN_FILE` | Path to file where tokens are stored | `.pt_ai_tokens.json` |

### 2. Sourcing the Script

Source the script in your pipeline to make the functions available:

```bash
source ./pt_ai_api.sh
```

### 3. Authenticating

Run `pt_ai_auth` to perform the initial sign-in and obtain tokens.

```bash
pt_ai_auth
```

### 4. Automated Workflow (Using Logs)

If you are running the `aisa` tool and capturing its logs, you can use `pt_ai_automate_process` to automatically set the working branch and generate reports based on the project ID found in the logs.

**Syntax:**
```bash
pt_ai_automate_process <LOG_FILE> <BRANCH_NAME> [REPORT_TYPES]
```

**Example:**
```bash
# Capture logs from aisa tool
aisa ... > aisa_debug.log 2>&1

# Automatically set working branch and generate PlainReport and Sarif reports
pt_ai_automate_process "aisa_debug.log" "$CI_COMMIT_REF_NAME" "PlainReport,Sarif"
```

This function will:
1.  Parse the Project ID from `aisa_debug.log`.
2.  Find the Branch ID corresponding to `$CI_COMMIT_REF_NAME`.
3.  Set that branch as the "working" branch.
4.  Find the ID of the last scan result.
5.  Generate and download the requested reports (e.g., `PlainReport.html`, `Sarif.json`).

### 5. Manual Usage

You can also use the underlying functions directly:

#### Generate Report
```bash
# pt_ai_generate_report <PROJECT_ID> <SCAN_RESULT_ID> <TEMPLATE_NAME> <OUTPUT_FILE> [LOCALE]
pt_ai_generate_report "project-uuid" "scan-uuid" "PlainReport" "report.html"
```

#### Set Working Branch
```bash
# pt_ai_set_working_branch <BRANCH_ID>
pt_ai_set_working_branch "branch-uuid"
```

#### Making API Requests
Use `pt_ai_api_request` to make authenticated calls. The function handles `Authorization` headers and token refreshing automatically.

**Syntax:**
```bash
pt_ai_api_request <METHOD> <ENDPOINT> [CURL_OPTIONS...]
```

**Examples:**

```bash
# GET request
response=$(pt_ai_api_request GET "/projects")
echo "$response"

# POST request with data
pt_ai_api_request POST "/scans" -d '{"projectId": "123"}'

# Upload a file
pt_ai_api_request POST "/projects/123/sources" -F "file=@source.zip"
```

## GitLab CI Example

```yaml
security_job:
  stage: security
  script:
    - source ./pt_ai_api.sh
    - pt_ai_auth
    # Run scan and capture logs
    - aisa ... > aisa_debug.log 2>&1 || true
    # Process results automatically
    - pt_ai_automate_process "aisa_debug.log" "$CI_COMMIT_REF_NAME" "PlainReport,Sarif"
  artifacts:
    paths:
      - PlainReport.html
      - Sarif.json
```
