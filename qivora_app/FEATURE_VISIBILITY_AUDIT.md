# Feature Visibility Audit

## Recently added features
1. Auth foundation (password service, repository, service, providers) - not connected to UI. LoginScreen still old demo login.
2. Schema v10 migration - active in DatabaseService.
3. Navigation: contacts push - active in home/chats.

## Not visible
- Auth features: no screens wired. Need implement UI in future phase.
- Navigation improvements: active but limited.

## Entry point
- main.dart -> QivoraApp -> MaterialApp.router with router. Correct.

## Stale build
- Not checked. Recommend flutter clean + rebuild if needed.

## Files needing changes (future)
- lib/features/auth/login_screen.dart (replace demo)
- Add register/forgot/reset screens.
- Router routes.

No code changes made in this audit.
