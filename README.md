# AzureArcBRTips

[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-EF9421.svg)](LICENSE-DOCS)

**English** · [Português](README.pt-BR.md)

Azure Monitor workbook for reviewing **Azure Arc Connected Machine agent versions, automatic upgrade health and extensions**. The current workbook version is **4.5.0**.

> Personal, independent project by Fabio Rodrigues Vieira Costa. Not an official Microsoft product or documentation, and not affiliated with or endorsed by Microsoft. Provided as is, without warranty. Read the [disclaimer](DISCLAIMER.md) before use.

## What it shows

- Agent version distribution, connectivity and estimated support status.
- Agents below the configurable security floor.
- Automatic upgrade eligibility, progress and failures.
- Azure Advisor recommendations and Azure Policy compliance.
- Extension versions, automatic upgrade coverage and issues grouped by cause.

The workbook UI and its detailed guides are available in English and Brazilian Portuguese. Latest-version references are read from Azure signals rather than a maintained version list. **Support status is an estimate**, not a guarantee of support or security; verify findings against the [official agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes).

## Get started

Read the [workbook guide](workbooks/arc-agent-support/README.md) for parameters, permissions, deployment and validation.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

- **Deploy:** the button deploys the template from the `main` branch and creates an Azure Monitor workbook in your selected resource group. You need permission to deploy the template and create that resource; Reader alone is not sufficient.
- **Manual import:** Azure Monitor → Workbooks → New → Advanced Editor → paste the [workbook JSON](workbooks/arc-agent-support-workbook.json) → Apply → Save.
- **Read data:** use Reader access to the subscriptions or management group being reviewed. Saving the workbook requires additional write permissions.

The workbook queries and validation script read Azure data; they do not upgrade agents or remediate resources. Deploying or saving the workbook does create or update a workbook resource. Review the artifacts, test outside production and follow your organization's policies.

## Repository

| Path | Purpose |
|---|---|
| [Workbook JSON](workbooks/arc-agent-support-workbook.json) | Workbook for manual import |
| [English guide](workbooks/arc-agent-support/README.md) / [Portuguese guide](workbooks/arc-agent-support/README.pt-BR.md) | Features, rules and usage |
| [ARM template](templates/arc-agent-support-azuredeploy.json) | Workbook deployment |
| [Validation script](scripts/Test-ArcAgentSupportWorkbook.ps1) | Smoke and Matrix checks against Azure |
| [Changelog](workbooks/arc-agent-support/CHANGELOG.md) | Workbook version history |

## Validation and privacy

The validation script requires **PowerShell 7+**, the **Az.Accounts** and **Az.ResourceGraph** modules, and an authenticated Azure context. Run from the repository root:

```powershell
Connect-AzAccount
./scripts/Test-ArcAgentSupportWorkbook.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Mode Smoke -OutFolder ./wb-test
```

Use `-Mode Matrix` for broader scenario coverage. These checks make live Azure requests and may encounter API throttling.

Workbook exports and test reports can contain machine names, resource IDs, subscription information and operational details. Keep them confidential; do not attach them to public issues or commits. The default test output directories are excluded by [.gitignore](.gitignore), but this does not replace reviewing what you publish.

## Feedback and security

For bugs and suggestions, [open an issue](https://github.com/fabiotreze/AzureArcBRTips/issues) with sanitized reproduction steps. Include the workbook version, deployment method and error message, but no credentials or environment data.

For vulnerabilities, follow the [security policy](SECURITY.md); do not disclose them in public issues.

## License and citation

- **Code, workbook JSON and ARM templates:** [MIT](LICENSE).
- **Standalone documentation:** [CC BY 4.0](LICENSE-DOCS).
- Third-party content and trademarks remain with their respective owners.

Suggested attribution: *AzureArcBRTips by Fabio Rodrigues Vieira Costa, https://github.com/fabiotreze/AzureArcBRTips*. Citation metadata is available in [CITATION.cff](CITATION.cff).

## Related project

[Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) provides a complementary point-in-time assessment. This repository focuses on the agent and extension workbook.
