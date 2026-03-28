# PT AI CLI Analysis

## Question
Can the default branch of a project be changed using `ptai-cli-plugin.jar` commands (`generate-report`, `json-ast`, `check-server`) and the provided `settings.json` configuration file?

## Findings

### CLI Commands (`spec.txt`)
*   **`generate-report`**: Generates a report for a specific branch. Accepts `--branch-name` (or `-b`).
*   **`json-ast`**: Runs a scan on a specific branch. Accepts `--branch-name` (or `-b`).
*   **`check-server`**: Checks connection to the server.

Neither command has a flag or option to set a branch as the default for the project. The `--branch-name` flag specifies the target for the current operation. If omitted, the tool uses the server-side default branch.

### Configuration File (`settings.json`)
*   The `BranchName` field (e.g., `"BranchName": "default"`) specifies the name of the branch to be scanned.
*   There are no fields in the schema (like `IsDefault` or `SetAsDefault`) that would configure the project's default branch.

## Conclusion
It is **not possible** to change the default branch using the provided CLI commands and configuration file. This functionality is likely managed via the PT AI web interface or a separate administrative API.
