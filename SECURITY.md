# Security Policy

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues, discussions, or pull requests.

Instead, report suspected vulnerabilities privately using [GitHub Private Vulnerability Reporting](https://github.com/ORNL/oscar/security/advisories/new) on `ORNL/oscar` (or contact the repository maintainer `@tyronechrisharris` directly).

Include:
- Affected repository and version/commit
- Deployment configuration prerequisites (if applicable)
- Minimal reproduction steps and impact assessment

## Security & Secret Hygiene Requirements

- Never commit TLS private keys, database passwords, admin passwords, backup encryption keys, `.env` files, or internal network addresses.
- All release dependencies in `web/oscar-viewer` must pass `npm run validate:dependencies` and `npm run audit:dependencies` with zero advisories.
