# Device Security Center

Recovered from [GFH-GhostsFromHell/electrical-workbench](https://github.com/GFH-GhostsFromHell/electrical-workbench), **without altering the original**.

This repository contains the JavaFX Windows desktop app, a standalone Spring Boot cloud portal based on the original device-security endpoints, the matching browser UI, unit tests and GitHub Actions workflows.

## Features and important safety limits

- Read-only local Windows BitLocker status check (never modifies BitLocker).
- **Manually selected single-file** AES-256-GCM encrypted **copy** with owner-held offline recovery key; original file is preserved.
- Optional password-wrapped cloud escrow storing ciphertext only; requires an independently saved recovery key and separately chosen passphrase.
- Operator-reviewed, single-use ciphertext retrieval and password-encrypted support chat.
- No recursive encryption, operating-system encryption, file deletion, lockout, persistence, or remote encryption commands.
- Limit of 64 MiB per file. Prototype only; encryption and authentication have **not been independently security-audited**. Do not use with important data without testing and review.

## Layout

- `device-security-desktop/` — original desktop application and tests.
- `portal/` — extracted cloud controllers, schema, browser UI and standalone auth/bootstrap.
- `.github/workflows/` — Windows build, Java test, and browser JS checks.

## Run locally

Requirements: JDK 21, Maven. Windows is required for BitLocker status and native packaging.

```powershell
mvn -B -f device-security-desktop/pom.xml test
mvn -B -f device-security-desktop/pom.xml javafx:run
```

Cloud portal must have strong **non-empty, unique** credentials supplied via environment variables:

```powershell
$env:DEVICE_ADMIN_USERNAME="operator"
$env:DEVICE_ADMIN_PASSWORD="<your strong unique operator password>"
$env:DEVICE_OWNER_USERNAME="owner"
$env:DEVICE_OWNER_PASSWORD="<your different strong owner password>"
mvn -B -f portal/pom.xml spring-boot:run
```

Portal opens at `http://localhost:8080/device-security.html`; browser sign-in requires the environment-configured credentials. For cloud hosting, configure HTTPS and persistent PostgreSQL (via `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`). Do not commit credentials.

For desktop connection to this local portal, set `PORTAL_URL=http://localhost:8080` before starting JavaFX. If unset, the **original** application defaults to the legacy hosted Electrical Workbench portal; this standalone repository does not automatically deploy a new hosted service.

The first version uses a file-based H2 database for local development. **Do not run it as a publicly exposed cloud service without hardening and a security audit.** The cloud service uses separately configured accounts, not the existing Electrical Workbench user database. Migrating stored records requires a deliberate data migration.

## Tests and Windows installers

```powershell
mvn -B -f portal/pom.xml test
mvn -B -f device-security-desktop/pom.xml clean verify
```

GitHub Actions `build-device-security-desktop.yml` produces a bundled-runtime unsigned MSI and portable Windows ZIP, available in each successful workflow run's artifacts. `build-device-security-portal.yml` runs cloud tests, and `validate-device-security-web.yml` checks browser scripts.

## Provenance

Device-security desktop files, device controllers, browser UI and selected tests are copied from the original public repository's `main` branch. The standalone Spring Boot configuration, top-level README and portal workflow are extraction-specific additions. **The source repository remains untouched.**

## Security notice

This repository is public. Never commit credentials, encryption keys, database files or user data. Publishing this code does not release software under an open-source license; no license has been granted.
