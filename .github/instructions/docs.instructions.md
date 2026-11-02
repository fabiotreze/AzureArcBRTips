---
applyTo: "**/*.md"
---
# Documentation files (Markdown)

- Every user-facing doc has an English file and a Portuguese (pt-BR) twin with the same structure. Edit both in the same change.
- Project READMEs keep this order: title · personal/unofficial notice linking `DISCLAIMER.md` · version/languages/mode line · language and changelog links · Deploy to Azure button · what it answers · quick path · tabs · requirements · import · validation performed · official documentation · known limits.
- The "Deploy to Azure" button uses the raw GitHub URL of `templates/<project>-azuredeploy.json`, URL-encoded, with `https://aka.ms/deploytoazurebutton`, in the same form as the existing projects.
- `CHANGELOG.md`: newest first, one entry per project version: `## <version> – <yyyy-mm-dd>` followed by short bullets. State "No query changed" when true.
- The root README lists projects only in the **Project catalog** table (Project | Purpose | Documentation). Add a row in both root READMEs; do not append loose sections.
- Claims about licensing, billing, support dates or APIs must link the official Microsoft Learn page (or the script / CVE record) and say "not verified" when unconfirmed. Summarize; do not paste Microsoft text.
- Do not include secrets, subscription or tenant IDs, internal URLs or customer names. Use placeholders such as `<subscription-id>`.
- Tone: neutral, precise, no marketing language; numbers that are estimates are labeled as estimates.
