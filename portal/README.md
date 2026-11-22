# Standalone cloud API

This directory extracts the original GHOST PROTOCOL controller, persistence schema,
browser UI and unit tests into its own Spring Boot 3.5 / Java 21 service.

This is intentionally **not** a copy of the full Electrical Workbench cloud portal.
The original app's account database, subscriptions, portal navigation, electrical tools
and other Spring services have not been copied.

SecurityConfig requires distinct owner and operator credentials from environment variables.
There are **no bundled passwords**. See the repository root README for setup.

The owner must retain the independent offline recovery key.
The server stores password-wrapped ciphertext only and does not encrypt files or Windows drives.
All production deployments need TLS, persistent database backups, account provisioning,
CSRF/rate-limit/abuse review, and a security audit.

The desktop defaults to the legacy remote portal unless PORTAL_URL is explicitly configured.
