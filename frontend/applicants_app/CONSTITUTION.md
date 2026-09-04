# HRMDO Applicant System — Constitution

This document defines the non-negotiable rules for the HRMDO Flutter application.

## Architecture

- **State management**: Riverpod (providers, not ChangeNotifier)
- **Routing**: GoRouter with `StatefulShellRoute.indexedStack`
- **Structure**: Feature-based folders (`features/<name>/`)
- **API**: Single `ApiClient` class with token management
- **No business logic in widgets** — providers handle data, screens handle UI

## Code Style

- **No comments** unless explicitly asked
- **No dead code** — delete unused functions, imports, variables
- **No hardcoded values** — use `AppColors`, `AppSpacing`, `AppRadius`, `AppTypography`
- **Named constructors** over factory methods when possible
- **`const` everywhere** — constructors, widgets, styles

## Security

- **Never commit** API keys, passwords, tokens, or secrets
- **Validate all inputs** before sending to the API
- **Sensitive operations** (hire, reject, archive) must confirm with user
- **Session tokens** managed only by `ApiClient`
- **No employee PII** in logs or breadcrumbs (names are OK, IDs are OK, but never SSN/addresses)

## Testing

- **Widget tests** for all new shared components
- **Provider tests** for new providers with API mocking
- **No test file imports non-existent modules**
- **Tests pass** before merge

## UI Consistency

- **Reuse existing widgets** — check `shared/widgets/` before creating new ones
- **Follow existing patterns** — check sibling files for styling conventions
- **Responsive** — use `LayoutBuilder` for breakpoints, not hardcoded sizes
- **Accessible** — proper contrast ratios, semantic labels where possible

## Data

- **Audit logging** — all state-changing operations logged to server
- **Soft delete only** — archive, never hard delete
- **Idempotent operations** — bulk actions must be safe to retry
- **Provider invalidation** — invalidate after mutations, never cache stale data
