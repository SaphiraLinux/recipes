# Security Policy

## Supported Versions

Saphira is currently under active development.

| Version / branch | Security support |
| ---------------- | ---------------- |
| `main` / current Saphira development | Supported |
| Historical recipe revisions, superseded package revisions and retired snapshots | Not supported |

Security corrections are made against the current maintained Saphira
recipe/package state. Historical Git commits remain available for
reference but are not independently maintained security branches.

## Reporting a Vulnerability

The preferred route is **GitHub Private Vulnerability Reporting** for
`SaphiraLinux/recipes` (the repository Security tab,
“Report a vulnerability” facility).

- Do **not** open a public GitHub issue for an undisclosed vulnerability.
- Use GitHub's private “Report a vulnerability” facility.
- Include the affected package/recipe/version/commit where known.
- Include reproduction details and prerequisites.
- Describe the expected security impact.
- Include suggested remediation if available.
- Never place passwords, private keys, tokens or other live credentials
  into a report.

Scope:

- Saphira recipe/build/package/patch vulnerabilities: report here.
- An upstream project's independent vulnerability: normally report
  upstream.
- However, report here too where Saphira's packaging, patching,
  defaults, integration or delayed update creates a Saphira-specific
  exposure.

Response expectations:

- We aim to acknowledge a valid report within 7 days.
- We aim to provide a meaningful status update within 14 days.
- These are response targets, not an SLA.
- Remediation and disclosure timing depends on severity and complexity.
- Please coordinate public disclosure until a fix or advisory can
  reasonably be prepared.

Accepted vulnerabilities may be handled through a GitHub Security
Advisory and credited to the reporter where appropriate. Reports may
be declined when they are not reproducible, not security relevant, or
wholly upstream with no Saphira-specific effect.

There is currently no vulnerability bounty programme.
