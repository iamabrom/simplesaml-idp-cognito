#!/bin/bash
# docker/entrypoint.sh — container initialisation before Apache starts
set -euo pipefail

CERT_DIR="/var/simplesamlphp/cert"
SSP_CFG="/var/simplesamlphp/config"
SSP_META="/var/simplesamlphp/metadata"

# ---------------------------------------------------------------------------
# 0. Ensure secrets are always set (config.php reads them via getenv)
# ---------------------------------------------------------------------------
if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
    export ADMIN_PASSWORD
    ADMIN_PASSWORD="$(openssl rand -base64 12)"
    echo ""
    echo "============================================"
    echo "  SimpleSAML IdP — Admin Credentials"
    echo "  Username: admin"
    echo "  Password: ${ADMIN_PASSWORD}"
    echo "============================================"
    echo ""
fi

if [[ -z "${SECRET_SALT:-}" ]]; then
    export SECRET_SALT
    SECRET_SALT="$(openssl rand -hex 32)"
fi

# ---------------------------------------------------------------------------
# 1. Generate self-signed SAML signing cert (RSA 3072, SHA-256, 30-day TTL)
# ---------------------------------------------------------------------------
mkdir -p "${CERT_DIR}"

if [[ ! -f "${CERT_DIR}/saml.key" ]] || [[ ! -f "${CERT_DIR}/saml.crt" ]]; then
    openssl req \
        -newkey rsa:3072 \
        -nodes \
        -x509 \
        -days 30 \
        -sha256 \
        -keyout "${CERT_DIR}/saml.key" \
        -out    "${CERT_DIR}/saml.crt" \
        -subj   "/CN=simplesaml-idp/O=SimpleSAML+IdP/C=US" \
        2>/dev/null
    echo "[entrypoint] Generated new SAML signing certificate (30-day self-signed)."
fi

# ---------------------------------------------------------------------------
# 2. Render saml20-sp-remote.php from template
#    If SP_ENTITY_ID / SP_ACS_URL are not set, write an empty metadata array
#    so SSP boots without errors.
# ---------------------------------------------------------------------------
SP_ENTITY_ID="${SP_ENTITY_ID:-}"
SP_ACS_URL="${SP_ACS_URL:-}"

if [[ -n "${SP_ENTITY_ID}" ]] && [[ -n "${SP_ACS_URL}" ]]; then
    sed \
        -e "s|__SP_ENTITY_ID__|${SP_ENTITY_ID}|g" \
        -e "s|__SP_ACS_URL__|${SP_ACS_URL}|g" \
        "${SSP_META}/saml20-sp-remote.php.tmpl" \
        > "${SSP_META}/saml20-sp-remote.php"
    echo "[entrypoint] SP remote metadata written (entity: ${SP_ENTITY_ID})."
else
    cat > "${SSP_META}/saml20-sp-remote.php" <<'PHP'
<?php
// No SP configured — set SP_ENTITY_ID and SP_ACS_URL env vars and redeploy.
$metadata = [];
PHP
    echo "[entrypoint] No SP_ENTITY_ID/SP_ACS_URL set — empty SP metadata written."
fi

# ---------------------------------------------------------------------------
# 3. Render authsources.php from template
#    If SIMPLESAML_USERS (JSON) is set, parse it with PHP and generate entries.
#    Otherwise generate a random password and create default alice/bob users.
# ---------------------------------------------------------------------------
if [[ -n "${SIMPLESAML_USERS:-}" ]]; then
    # Parse the JSON user array with PHP and build the PHP user-entry block.
    USERS_BLOCK="$(php -r "
        \$users = json_decode(getenv('SIMPLESAML_USERS'), true);
        if (!is_array(\$users) || empty(\$users)) {
            fwrite(STDERR, '[entrypoint] ERROR: SIMPLESAML_USERS is not valid JSON.\n');
            exit(1);
        }
        \$out = '';
        foreach (\$users as \$u) {
            \$username = \$u['u'];
            \$password = \$u['p'];
            \$email    = isset(\$u['email'])  ? \$u['email']  : \$username . '@example.com';
            \$groups   = isset(\$u['groups']) ? \$u['groups'] : 'users';
            \$given    = ucfirst(\$username);
            \$key      = str_replace(\"'\", \"\\\\'\", \$username . ':' . \$password);
            \$out .= \"        '\" . \$key . \"' => [\n\";
            \$out .= \"            'uid'       => ['\" . str_replace(\"'\", \"\\\\'\", \$username) . \"'],\n\";
            \$out .= \"            'email'     => ['\" . str_replace(\"'\", \"\\\\'\", \$email)    . \"'],\n\";
            \$out .= \"            'givenName' => ['\" . str_replace(\"'\", \"\\\\'\", \$given)    . \"'],\n\";
            \$out .= \"            'sn'        => ['User'],\n\";
            \$out .= \"            'groups'    => ['\" . str_replace(\"'\", \"\\\\'\", \$groups)   . \"'],\n\";
            \$out .= \"        ],\n\";
        }
        echo rtrim(\$out, \"\n\");
    ")"
else
    RAND_PASS="$(openssl rand -base64 12)"
    USERS_BLOCK="        'alice:${RAND_PASS}' => [
            'uid'       => ['alice'],
            'email'     => ['alice@example.com'],
            'givenName' => ['Alice'],
            'sn'        => ['User'],
            'groups'    => ['users'],
        ],
        'bob:${RAND_PASS}' => [
            'uid'       => ['bob'],
            'email'     => ['bob@example.com'],
            'givenName' => ['Bob'],
            'sn'        => ['User'],
            'groups'    => ['users'],
        ],"

    echo ""
    echo "============================================"
    echo "  SimpleSAML IdP — Default Users Created"
    echo "  alice / ${RAND_PASS}"
    echo "  bob   / ${RAND_PASS}"
    echo "============================================"
    echo ""
fi

# Write block to a temp file so PHP can read it without shell quoting issues.
printf '%s\n' "${USERS_BLOCK}" > /tmp/ssp_users_block.txt

php -r "
    \$tmpl  = file_get_contents('${SSP_CFG}/authsources.php.tmpl');
    \$block = file_get_contents('/tmp/ssp_users_block.txt');
    file_put_contents('${SSP_CFG}/authsources.php', str_replace('__USERS_BLOCK__', \$block, \$tmpl));
"

rm -f /tmp/ssp_users_block.txt
echo "[entrypoint] authsources.php rendered."

# ---------------------------------------------------------------------------
# 4. Write static files for the landing page and health check
# ---------------------------------------------------------------------------
mkdir -p /var/www/html

echo "OK" > /var/www/html/healthz

cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>SimpleSAML IdP</title>
  <style>body{font-family:sans-serif;max-width:600px;margin:3rem auto;line-height:1.6}</style>
</head>
<body>
  <h1>SimpleSAML Identity Provider</h1>
  <p>This container provides a lightweight SAML 2.0 IdP for Cognito federation exercises.</p>
  <ul>
    <li><a href="/simplesaml/">SimpleSAMLphp admin panel</a></li>
    <li><a href="/simplesaml/saml2/idp/metadata.php">IdP metadata (give this URL to Cognito)</a></li>
  </ul>
</body>
</html>
HTML

# ---------------------------------------------------------------------------
# 5. Fix ownership so www-data (Apache) can read/write everything it needs
# ---------------------------------------------------------------------------
chown -R www-data:www-data \
    /var/simplesamlphp \
    /var/www/html

echo "[entrypoint] Initialisation complete — starting Apache."

exec "$@"
