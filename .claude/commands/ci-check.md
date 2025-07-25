# GitHub PR CI Check Command

Check CI status for the current branch's PR and get failure details.

## Usage
```bash
/ci-check
```

## Instructions
1. Get the current branch name
2. Find the PR associated with this branch
3. Check CI status using GitHub CLI
4. Display failed checks with details
5. Show logs for failed checks

## Implementation
First, get the current branch using `git branch --show-current`.

Use `gh pr list --head [CURRENT_BRANCH]` to find the PR for this branch.
Use `gh pr checks` to get detailed check information for the PR.
For failed checks, use `gh run view` to show failure logs.

Display results in a clear format showing:
- Current branch and associated PR
- Overall CI status
- Failed check names
- Error messages and logs
- Suggestions for common fixes

If no PR exists for the current branch, suggest creating one first.