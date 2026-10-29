# security
Record each finding and its fix with bin/ledger (phase=security).

## When to Use
- Code that handles user input, auth, secrets, files, network, SQL or shell; before shipping such code.

## Steps
1. Map trust boundaries: where untrusted data enters and where it is used.
2. Validate and encode at the boundary: parameterized queries, no string-built shell or SQL, path normalization, size and type limits.
3. Auth: check authorization on every request server-side, least privilege, deny by default.
4. Secrets: never in code, logs or errors; load from env or a secret store; rotate anything exposed.
5. Dependencies: pin, scan, remove unused.
6. Errors and logs: no stack traces or sensitive data to clients.
7. Write a test for each abuse case you fix (injection string, missing token, other user's id).

## Red Flags
- Client-side checks as the only guard; `eval`, `shell=True` or string-concatenated queries with input.
- "Internal only" used as a reason to skip validation.
- Secrets in a diff or log line.

## Verification
- Abuse-case tests fail before and pass after; grep of the diff shows no secrets; unauthenticated and cross-user requests are rejected.
