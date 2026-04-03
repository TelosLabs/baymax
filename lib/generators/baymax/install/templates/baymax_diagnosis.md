# Baymax Diagnosis Template

This template documents the expected format for Baymax-created GitHub issues.

## Issue Structure

### Title
`[baymax] ErrorClass: Truncated error message...`

### Body
- Source, severity, occurrence count
- Error class and message
- Root cause analysis (from LLM triage)
- Confidence score and security tier
- Affected files
- Suggested fix
- Decision (action and reason)

### Machine-readable metadata
Embedded as HTML comments:
- `<!-- toolkit:fingerprint:sha1:HASH -->` — deduplication fingerprint
- `<!-- toolkit:metadata:JSON -->` — full structured metadata
