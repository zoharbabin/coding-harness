# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.x     | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in Karen, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

### How to Report

Email: security@example.com (replace with maintainer contact)

Or open a [GitHub Security Advisory](https://github.com/zoharbabin/karen/security/advisories/new).

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if known)

### Disclosure Process

1. Report received — acknowledgment within 48 hours.
2. Validation and CVE assignment if applicable.
3. Fix developed and tested.
4. Coordinated disclosure: fix released, advisory published.
5. Credit given to reporter (unless anonymity requested).

We follow responsible disclosure. Please give us reasonable time to address
issues before public disclosure.

## Security Design

Karen runs gate scripts as child processes. Gate script paths are validated
to be within `.karen/gates/` before execution. Karen never passes user input
to shell commands — `os/exec` is always called with explicit argument arrays.
