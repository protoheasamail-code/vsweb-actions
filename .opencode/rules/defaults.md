# Default Rules

These are generic best practices applied to all projects. **AGENTS.md takes precedence over all defaults.**

**Priority Order:**
1. AGENTS.md (HIGHEST - STRICTLY ENFORCED)
2. CONTRIBUTING.md (secondary)
3. Custom rules in `.opencode/rules/` (lowest)
4. These defaults (FALLBACK ONLY)

If AGENTS.md exists, its rules are ALWAYS enforced and cannot be overridden by these defaults.

## Code Quality

### SOLID Principles
- **S**ingle Responsibility: One class/function does one thing
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: Many specific interfaces over general ones
- **D**ependency Inversion: Depend on abstractions, not concretions

### Naming
- Use descriptive names
- Follow project conventions exactly
- No abbreviations unless common (i.e., id, url, api)
- Boolean names should be is/has/can/should

### Comments
- Only for business logic intent
- Don't comment what code does, explain why
- No commented-out code
- Update comments when code changes

### Anti-Patterns to Avoid
- God classes (too many responsibilities)
- Magic numbers (use constants)
- Deep nesting (max 3 levels)
- Unused parameters
- Mutable exposed state

## Robustness

### Null Safety
- Handle null/empty values explicitly
- Use optional types when available
- Validate input at boundaries
- Don't return null unexpectedly

### Error Handling
- Catch specific exceptions
- Don't swallow errors silently
- Provide meaningful error messages
- Log errors appropriately

### Edge Cases
- Empty collections
- Zero values
- Concurrent access
- Network failures
- Permission denied
- Invalid input

## Testing

### Unit Tests
- Test one thing at a time
- Use descriptive test names
- Arrange-Act-Assert pattern
- Don't test implementation details

### Integration Tests
- Test真实 workflows
- Mock external dependencies
- Clean up after tests

## Security

### Never
- Hardcode secrets
- Log sensitive data
- Expose internal details in errors
- Trust user input

### Always
- Validate input
- Sanitize output
- Use parameterized queries
- Follow principle of least privilege
