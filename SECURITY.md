# Security policy

OpenVINO-Nim-API is a community-maintained binding. Please do not disclose a
suspected vulnerability in a public issue, pull request or code comment.

## Reporting

Use [GitHub private vulnerability reporting](https://github.com/AbyssGG/OpenVINO-Nim-API/security/advisories/new)
when it is available. If GitHub does not show that form, open a minimal issue
asking for a private contact route and do not include exploit details. Reports
should include the affected commit or version, operating system, Nim version,
OpenVINO runtime version, reproduction steps and the smallest safe proof.

## Scope

Reports about this repository include the managed API, raw ABI declarations,
loader, release scripts and CI workflows. Vulnerabilities in the OpenVINO
runtime itself should also be reported to the upstream OpenVINO project.

The package does not bundle the runtime, model weights or credentials. Never
attach a proprietary model, a runtime binary or a secret to a report.

## Supported versions

Only the latest commit on `main` and the most recent published package version
are actively maintained while `0.1.0` is unreleased. Older commits are useful
for archaeology but should not be assumed to receive security fixes.

We will acknowledge a report when practical, keep the report private while a
fix is prepared, and document the impact and remediation in the release notes.
