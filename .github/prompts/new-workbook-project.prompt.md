---
description: Add or update a workbook project end to end in AzureArcBRTips (files, docs EN/PT, template, catalog, validation)
agent: agent
---
You are working in the AzureArcBRTips repository. Follow `.github/copilot-instructions.md`. Do not commit or push.

Project: ${input:project:Folder name, e.g. arc-sql-payg-readiness}
Version: ${input:version:e.g. 2.3.0}
What changed (one line, English): ${input:change:Short summary}

Do the following, in order, and report each step:
1. Check that these exist and list any that are missing: `workbooks/${input:project}-workbook.json`, `workbooks/${input:project}/README.md`, `workbooks/${input:project}/README.pt-BR.md`, `workbooks/${input:project}/CHANGELOG.md`, `templates/${input:project}-azuredeploy.json`.
2. Do NOT edit the workbook JSON. If it needs a change, write a script and ask me to run it.
3. Update `workbooks/${input:project}/CHANGELOG.md` with a new top entry for the version and date (today), and the "Current version" line in both project READMEs.
4. Make sure the root `README.md` and `README.pt-BR.md` "Project catalog" tables have one row for this project (add if missing, same format as the other rows).
5. Check every relative link in the project READMEs resolves to an existing file.
6. Print the exact commands I must run, from the repo root: regenerate the ARM template from the workbook; run `scripts/Test-ArcWorkbookQueries.ps1` with `-DryRun`, `-Language PT`, `-Language EN` and `-Burst`; then `git diff --stat`.
7. Finish with a checklist of what is verified, what is not verified, and the suggested commit message.
