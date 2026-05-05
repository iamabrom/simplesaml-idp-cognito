# simplesaml-idp-cognito

A lightweight **SAML 2.0 Identity Provider** container built on
[SimpleSAMLphp 2.5](https://simplesamlphp.org/), designed to run on
**AWS App Runner** for short-lived Cognito federation experimenting.

> **Not for production.** This IdP uses a self-signed cert, no database, and file-based PHP sessions. It is intentionally ephemeral — everything resets when the container restarts. Use it to learn how Cognito SAML federation works, then swap in a real IdP.

---

## Using the pre-built image

```bash
docker pull ghcr.io/iamabrom/simplesaml-idp-cognito:latest
```

Run it locally with SP values already known:

```bash
docker run --rm -p 8080:8080 \
  -e SP_ENTITY_ID=urn:amazon:cognito:sp:<your-pool-id> \
  -e SP_ACS_URL=https://<your-cognito-domain>/saml2/idpresponse \
  ghcr.io/iamabrom/simplesaml-idp-cognito:latest
```

Or without SP values — alice/bob credentials will be printed to stdout and the IdP will accept any SP:

```bash
docker run --rm -p 8080:8080 ghcr.io/iamabrom/simplesaml-idp-cognito:latest
```

---

## Quick start (local, from source)

```bash
git clone https://github.com/<your-org>/simplesaml-idp-cognito.git
cd simplesaml-idp-cognito
docker compose up --build
```

Open <http://localhost:8080/> — the landing page links to the SSP admin panel
and the IdP metadata URL.

**Default credentials** (alice and bob) are printed to the container logs on
first start:

```
============================================
  SimpleSAML IdP — Default Users Created
  alice / <random-password>
  bob   / <random-password>
============================================
```

Retrieve them with `docker compose logs idp`.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ADMIN_PASSWORD` | random (printed to logs) | Password for the SSP admin panel (`/simplesaml/`) — username is always `admin` |
| `SECRET_SALT` | random | Cryptographic salt used internally by SSP |
| `SP_ENTITY_ID` | _(empty)_ | Cognito SP entity ID — `urn:amazon:cognito:sp:<pool-id>` |
| `SP_ACS_URL` | _(empty)_ | Cognito ACS URL — `https://<domain>/saml2/idpresponse` |
| `SIMPLESAML_USERS` | _(empty — alice/bob created)_ | JSON array of custom users (see below) |

### Custom users (`SIMPLESAML_USERS`)

Pass a JSON array of user objects:

```json
[
  {"u": "user1", "p": "secret", "email": "user1@example.com", "groups": "developers"},
  {"u": "user2", "p": "secret", "email": "user2@example.com", "groups": "users"}
]
```

All fields except `u` and `p` are optional (`email` defaults to `<u>@example.com`,
`groups` defaults to `users`).

---

## Deploying to AWS App Runner

### 1. Get the image

A pre-built multi-arch image (amd64 + arm64) is published to GHCR on every push to `main`:

```
ghcr.io/iamabrom/simplesaml-idp-cognito:latest
```

If you'd prefer to host the image yourself, fork this repo — the included
GitHub Actions workflow (`.github/workflows/publish.yml`) will publish to your
own GHCR namespace automatically. You can also push to ECR and configure App
Runner to pull from there instead.

### 2. Create the App Runner service

1. In the AWS console, go to **App Runner → Create service**.
2. **Source**: Container registry → select your image URI.
3. **Port**: `8080`.
4. **Health check path**: `/healthz`.
5. Set environment variables:
   - **`ADMIN_PASSWORD`** — set this to a value you choose, or leave blank and retrieve it from the CloudWatch logs after deploy (username is always `admin`).
   - **If you already have a Cognito user pool**, set `SP_ENTITY_ID` and `SP_ACS_URL` now:
     - `SP_ENTITY_ID` = `urn:amazon:cognito:sp:<your-user-pool-id>`
     - `SP_ACS_URL` = `https://<your-cognito-domain>/saml2/idpresponse`
   - **If you don't have a pool yet**, leave both blank — you can update the service after creating the Cognito user pool.
6. Deploy.

App Runner gives you a URL like `https://xxxxxxxxxxxx.us-east-1.awsapprunner.com`.

---

## Usage flow: wiring up Cognito SAML federation

Follow the below steps after your App Runner service is running. These are general steps, refer to the official [Cognito developer guide](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-managing-saml-idp.html) for the latest information.

### Step 1 — Grab the IdP metadata URL

```
https://<apprunner-url>/simplesaml/saml2/idp/metadata.php
```

Copy this URL; you'll paste it into Cognito.

### Step 2 — Check the generated user credentials

Open the App Runner service in the console → **Logs** (CloudWatch).  
Look for the banners printed at startup — one for the admin panel credentials
(if `ADMIN_PASSWORD` was not set) and one for the default user credentials
(if `SIMPLESAML_USERS` was not set).

### Step 3 — Create a Cognito SAML IdP

1. Open your **Cognito user pool** → **Authentication** → **Social and external providers**.
2. Choose **Add identity provider → SAML**.
3. Paste the IdP metadata URL from Step 1.
4. Note the SP values Cognito shows you:
   - **Cognito SAML identifier (entity ID)**: `urn:amazon:cognito:sp:<pool-id>`
   - **ACS URL**: `https://<cognito-domain>/saml2/idpresponse`

### Step 4 — Feed the SP values back to the IdP

Update the App Runner service environment variables:

| Variable | Value |
|---|---|
| `SP_ENTITY_ID` | `urn:amazon:cognito:sp:<pool-id>` |
| `SP_ACS_URL` | `https://<cognito-domain>/saml2/idpresponse` |

App Runner redeploys in ~30 seconds with no downtime.

### Step 5 — Configure Cognito attribute mapping

In your Cognito SAML provider settings, map SAML attributes to Cognito
attributes:

| SAML attribute | Cognito attribute |
|---|---|
| `email` | `email` |
| `givenName` | `given_name` |
| `sn` | `family_name` |

### Step 6 — Test federated login

Use the Cognito Managed Login to trigger a SAML login. Enter the alice or bob
credentials from Step 2, or whatever users you set via `SIMPLESAML_USERS`.

---

## Key URLs

| URL | Purpose |
|---|---|
| `/` | Landing page |
| `/healthz` | Health check (plain text `OK`) |
| `/simplesaml/` | SimpleSAMLphp admin panel |
| `/simplesaml/saml2/idp/metadata.php` | IdP SAML metadata (give to Cognito) |

---

## Security caveats

- **Self-signed cert** — rotated every 30 days on container restart. Cognito fetches the cert from the metadata URL so it always has the current cert, but any in-flight sessions at rotation time will fail.
- **No persistent storage** — sessions, certs, and generated passwords are lost on restart.
- **No rate limiting or brute-force protection** — this is for learning, not for guarding real identities.
- **Do not use this IdP to protect real user accounts or production resources.**

---

## Local development tips

```bash
# Rebuild after config changes
docker compose up --build

# Tail logs (credentials are here)
docker compose logs -f idp

# Override users without rebuilding
SP_ENTITY_ID=urn:test SP_ACS_URL=https://example.com/acs docker compose up
```

---

## License

This repository's code is MIT licensed — see [LICENSE](LICENSE).

The container image includes [SimpleSAMLphp](https://simplesamlphp.org/), which is licensed under the [GNU Lesser General Public License v2.1](https://github.com/simplesamlphp/simplesamlphp/blob/master/LICENSE).
