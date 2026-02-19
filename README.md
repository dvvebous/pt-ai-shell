# PT AI Enterprise Server API Integration for CI/CD

This repository contains a Bash script to facilitate integration with PT AI Enterprise Server API in CI/CD pipelines (e.g., GitLab CI).

## Features

- **Authentication**: Uses `AISA_HOST` and `AISA_TOKEN` for direct authentication.
- **Insecure SSL Support**: Optional support for self-signed certificates via `PT_AI_INSECURE_SSL`.
- **Report Generation**: Automatically generates and downloads reports (PlainReport, Sarif) for the last scan.
- **Branch Management**: Sets the default/working branch automatically.
- **Log Parsing**: Parses execution logs (e.g., from `ptai-cli-plugin`) to automatically identify the project and branch for subsequent API actions.

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
| `AISA_HOST` | Base URL of PT AI Enterprise Server (e.g., `https://pt-ai.example.com`) | Required |
| `AISA_TOKEN` | API Token for PT AI | Required |
| `PT_AI_API_VERSION` | API version number (e.g., `2`). Set to empty string if version is not in the URL path. | `2` (or empty if updated) |
| `PT_AI_INSECURE_SSL` | Set to `true` to skip SSL verification (e.g., for self-signed certs) | `false` |

### 2. Sourcing the Script

Source the script in your pipeline to make the functions available:

```bash
source ./pt_ai_api.sh
```

### 3. Automated Workflow (Using Logs)

If you are running the `ptai-cli-plugin` (AISA tool) and capturing its logs, you can use `pt_ai_automate_process` to automatically set the working branch and generate reports based on the Branch ID found in the logs.

**Syntax:**
```bash
pt_ai_automate_process <LOG_FILE> <BRANCH_NAME> [REPORT_TYPES]
```

**Example:**
```bash
# Capture logs from tool
java -jar ptai-cli-plugin.jar ... | tee scan.log

# Automatically set working branch and generate PlainReport and Sarif reports
pt_ai_automate_process "scan.log" "$CI_COMMIT_REF_NAME" "PlainReport,Sarif"
```

This function will:
1.  Parse the Branch ID directly from `scan.log`.
2.  Set that branch as the "working" branch.
3.  (Optional) Find the Project ID and ID of the last scan result.
4.  (Optional) Generate and download the requested reports (e.g., `PlainReport.html`, `Sarif.json`).

### 4. Manual Usage

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
Use `pt_ai_api_request` to make authenticated calls.

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
```

## GitLab CI Example

```yaml
security_job:
  stage: security
  script:
    - |
      set -o pipefail
      # Run scan and capture logs
      java -jar /opt/ptai/bin/ptai-cli-plugin.jar ... | tee .report/ptai-scan.log

      source ./pt_ai_api.sh
      # Process results automatically
      pt_ai_automate_process ".report/ptai-scan.log" "$CI_COMMIT_REF_NAME" "PlainReport,Sarif"
  artifacts:
    paths:
      - PlainReport.html
      - Sarif.json
```
