# GitHub PR CI Fix Command

Automatically fix CI failures for the current branch's PR.

## Usage
```bash
/ci-fix
```

## Instructions
1. First run PR CI check to identify failures
2. Analyze common CI failure patterns
3. Apply appropriate fixes automatically
4. Run tests locally if possible
5. Commit and push fixes

## Implementation
Start by running the PR CI check command to get failure details.

Common CI fixes to implement:
- Linting errors: Run linter and fix automatically
- Type errors: Analyze and fix TypeScript/type issues
- Test failures: Run tests locally and fix failing tests
- Build failures: Check dependencies and build configuration
- Security issues: Update dependencies or fix security vulnerabilities

For each type of failure:
1. Parse the error message to understand the issue
2. Apply the appropriate fix using available tools
3. Verify the fix locally when possible
4. Commit changes with descriptive message

After fixes, suggest re-running CI or pushing changes.