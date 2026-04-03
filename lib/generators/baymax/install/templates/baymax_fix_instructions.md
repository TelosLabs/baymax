# Baymax Fix Instructions

You are fixing a production error that was automatically triaged by Baymax.

## Instructions
1. Read the linked issue carefully — it contains the root cause analysis and suggested fix
2. Focus ONLY on the affected files listed in the issue
3. Write a minimal, targeted fix — do not refactor surrounding code
4. Add or update tests to cover the error scenario
5. Include `Fixes #ISSUE_NUMBER` in your PR description

## Constraints
- Do NOT modify files outside the affected files list unless absolutely necessary
- Do NOT add new dependencies
- Do NOT change database schema or run migrations
- Keep the PR small and focused — one fix per issue
- If you are unsure about the fix, add a comment on the issue explaining what you found

## PR Labels
Add the `baymax-fix` label to your PR to trigger automated verification.
