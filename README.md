# AzureArcBRTips

[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-EF9421.svg)](LICENSE-DOCS)

**English** · [Português](README.pt-BR.md)

A collection of **projects, workbooks, scripts, deployment templates and practical guidance for Azure Arc**. AzureArcBRTips is the home for multiple initiatives, each with its own purpose, prerequisites, usage instructions and version history.

> Personal, independent project by Fabio Rodrigues Vieira Costa. Not an official Microsoft product or documentation, and not affiliated with or endorsed by Microsoft. Provided as is, without warranty. Read the [disclaimer](DISCLAIMER.md) before use.

## Project catalog

| Project | Purpose | Documentation |
|---|---|---|
| Arc Agent Support Workbook | Agent version compliance, automatic upgrade health, Advisor, Policy and extensions | [English](workbooks/arc-agent-support/README.md) · [Português](workbooks/arc-agent-support/README.pt-BR.md) · [Changelog](workbooks/arc-agent-support/CHANGELOG.md) |

The catalog lists projects currently available in this repository. Future projects will be added as they are published. Project versions are independent; the workbook's version is not a version for the entire repository.

## Get started

1. Choose a project from the catalog.
2. Read its guide for prerequisites, required permissions, limitations and validation steps.
3. Review the code and any deployment template before running it.
4. Test outside production and assess Azure costs and organizational policies.

For the current workbook, the [project guide](workbooks/arc-agent-support/README.md) includes the **Deploy to Azure** button, manual import, configurable rules and validation commands. Its queries are read-only, but deploying or saving it creates or updates a workbook resource. Do not assume future projects are read-only; check each project's documented behavior.

## Repository

| Path | Purpose |
|---|---|
| [workbooks/](workbooks/) | Azure Monitor workbook JSON and project-specific guides and changelogs |
| [scripts/](scripts/) | Scripts for validation, automation or other project tasks |
| [templates/](templates/) | Azure resource deployment templates |
| Root documentation | Repository overview, licenses, citation, disclaimer and security policy |

The repository is organized by artifact type. A project guide connects its related workbook, scripts and templates. Existing artifact paths are preserved for links and deployments.

## Adding future projects

- Add an entry to the catalog in both root README files.
- Use descriptive artifact names and a dedicated project guide; avoid overwriting another project's files.
- Document purpose, prerequisites, permissions, read/write effects, costs, limitations, deployment, validation and version history.
- Link related artifacts from the project guide. Put project-specific details and deployment buttons there rather than treating the root as a single-project guide.
- Add directories for new artifact types only when there is content to publish.

## Privacy and safe use

Exports, script output and test reports can contain machine names, resource IDs, subscription information and operational details. Keep them confidential; do not attach them to public issues or commits. The workbook's default test output directories are excluded by [.gitignore](.gitignore), but custom output locations and future projects need their own review.

Use least privilege and validate recommendations against current official documentation. Analysis results are not a guarantee of support, security or compliance. See the [disclaimer](DISCLAIMER.md).

## Feedback and security

For bugs and suggestions, [open an issue](https://github.com/fabiotreze/AzureArcBRTips/issues) with sanitized reproduction steps. Include the project name, version or commit, execution/deployment method and error message, but no credentials or environment data.

For vulnerabilities, follow the [security policy](SECURITY.md); do not disclose them in public issues.

## License and citation

- **Code, scripts, workbook JSON and deployment templates:** [MIT](LICENSE).
- **Standalone documentation:** [CC BY 4.0](LICENSE-DOCS).
- Third-party content and trademarks remain with their respective owners.

Suggested attribution: *AzureArcBRTips by Fabio Rodrigues Vieira Costa, https://github.com/fabiotreze/AzureArcBRTips*. Citation metadata is available in [CITATION.cff](CITATION.cff).

## Related project

[Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) is a separate repository for point-in-time Azure Arc security assessments.
