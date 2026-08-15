# Security policy

## Reporting a vulnerability

Please do not open a public issue for security vulnerabilities, exposed
credentials, signing material, or privacy problems. Use GitHub's private
security-advisory flow instead:

1. Open the **Security** tab of this repository.
2. Choose **Advisories**.
3. Select **Report a vulnerability**.

Include the affected version, reproduction steps, impact, and any suggested
fix. Please avoid including real IPTV credentials, playlist URLs, personal
data, or copyrighted media in the report.

## Supported version

Security fixes are applied to the latest released version of Lumen. Users
should update to the newest available build before reporting an issue.

## Sensitive files

The following must never be committed or attached to issues and pull requests:

- Android keystores and `key.properties`
- App Store or Play Console credentials
- Provider usernames, passwords, and playlist URLs
- API tokens and service-account files
- Real user data or logs containing credentials

If you accidentally publish a secret, revoke or rotate it immediately and
contact the maintainer through a private security advisory.
