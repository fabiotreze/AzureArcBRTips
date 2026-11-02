---
applyTo: "workbooks/*.json,templates/*.json"
---
# Workbook and template files

- These files are **generated or script-edited**, never hand-edited or reformatted by an assistant. If a change is requested, produce a script (PowerShell 7 or Python) that edits the JSON by structure (parse, change, write back) and prints a summary of what changed.
- After any edit: confirm the file parses as JSON, that it is UTF-8 without BOM, and that no `{Parameter}` is referenced without being defined.
- Do not shorten, reorder or "clean up" queries. Query changes need a reason, a test result and a changelog line.
- Keep every item that depends on a language behind `Language` conditional visibility; keep one bilingual tab bar.
- Never put subscription IDs, tenant IDs, resource IDs or tokens in a workbook default value.
- A workbook change is not finished until: the editorial changelog inside the workbook, `workbooks/<project>/CHANGELOG.md`, the "Current version" line in both READMEs, and `templates/<project>-azuredeploy.json` are updated (regenerate the template from the workbook; set contentVersion to the project version; workbookId stays [newGuid()]).
- Validation commands (run from the repo root; replace the placeholders):
  `./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath <workbook.json> -Subscriptions <subscription-id> -DryRun`
  then `-Language PT`, `-Language EN`, and `-Burst`.
