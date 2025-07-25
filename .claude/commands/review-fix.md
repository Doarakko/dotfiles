# GitHub PR Review Comment Fix Command

Automatically check PR review comments and apply the requested fixes.

## Usage
```bash
/review-fix [pr-number]
```

If no PR number is provided, uses the current branch's PR.

## Instructions
1. Fetch the PR and its review comments using GitHub CLI
2. Analyze each review comment for actionable feedback
3. Apply the requested changes automatically when possible
4. Run tests and linting to ensure fixes are correct
5. Commit changes with reference to review feedback
6. Push changes and notify about completion

## Implementation
Start by getting the current PR information and review comments.

### Step 1: Get PR Information
```bash
# Get current branch PR if no number provided
gh pr view --json number,reviewRequests,reviews,url

# Or get specific PR
gh pr view {pr-number} --json number,reviewRequests,reviews,url
```

### Step 2: Fetch Review Comments
```bash
# Get review comments with file context
gh pr view {pr-number} --json reviews
gh api repos/:owner/:repo/pulls/{pr-number}/comments
```

### Step 3: Parse and Categorize Comments
For each review comment:
1. **Code suggestions**: Apply suggested code changes directly
2. **Style/formatting**: Run appropriate linters/formatters
3. **Logic issues**: Analyze and implement requested logic changes  
4. **Documentation**: Update comments, README, or docs as requested
5. **Testing**: Add or modify tests as suggested
6. **Security concerns**: Address security-related feedback

### Step 4: Apply Fixes Systematically
- Use file path and line number from review comments to locate exact changes needed
- For code suggestions, apply the suggested diff directly
- For broader feedback, implement comprehensive fixes
- Validate each fix doesn't break existing functionality

### Step 5: Verify and Commit
```bash
# Run tests if available
npm test || python -m pytest || go test || cargo test

# Run linting
npm run lint || ruff check || golangci-lint run

# Commit with descriptive message
git add .
git commit -m "fix: address PR review feedback

- Applied code suggestions from review
- Fixed style/formatting issues  
- Updated documentation as requested
- Added requested test coverage

Addresses review comments in PR #{pr-number}"

# Push changes
git push
```

### Step 6: Update PR
```bash
# Add comment about fixes applied
gh pr comment {pr-number} --body "🤖 Applied review feedback:
- [List of specific changes made]
- All tests passing
- Linting issues resolved

Ready for re-review!"
```

## Error Handling
- If review comments are unclear, ask for clarification in PR comment
- If automated fix isn't possible, create TODO comments and notify in PR
- If tests fail after fixes, revert and request guidance
- Handle merge conflicts gracefully

## Notes
- Only apply changes that are clearly requested and safe
- For complex logic changes, implement conservatively and ask for confirmation
- Preserve existing code style and patterns
- Always run tests before committing fixes