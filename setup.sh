#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.0.0"

# ============================================================
# NGINX XRAY INSTALLER
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[+]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

trap 'die "Installation failed on line $LINENO."' ERR

# ------------------------------------------------------------
# ROOT
# ------------------------------------------------------------

[[ "$EUID" -eq 0 ]] || die "Run this installer as root."

# ------------------------------------------------------------
# OS
# ------------------------------------------------------------

[[ -f /etc/os-release ]] || die "Cannot detect operating system."

source /etc/os-release

case "$ID" in
    ubuntu|debian)
        ;;
    *)
        die "Supported systems: Debian and Ubuntu."
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# BANNER
# ------------------------------------------------------------

clear

echo
echo "============================================================"
echo "          NGINX + XRAY REVERSE PROXY INSTALLER"
echo "============================================================"
echo
echo "Version: $VERSION"
echo

# ------------------------------------------------------------
# INPUT
# ------------------------------------------------------------

read -rp "Enter your root domain name: " DOMAIN

DOMAIN="${DOMAIN,,}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"

[[ -n "$DOMAIN" ]] || die "Domain cannot be empty."

[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]] ||
    die "Invalid domain."

echo
read -rp "Enter your panel path (example: /panel): " PANEL_PATH

[[ -n "$PANEL_PATH" ]] || die "Panel path cannot be empty."

[[ "$PANEL_PATH" == /* ]] || PANEL_PATH="/$PANEL_PATH"

if [[ "$PANEL_PATH" != "/" ]]; then
    PANEL_PATH="${PANEL_PATH%/}"
fi

case "$PANEL_PATH" in
    /ws|/ws/*|/xhttp|/xhttp/*|/gprc|/gprc/*)
        die "Panel path conflicts with an Xray path."
        ;;
esac

echo
read -rp "Enter your panel backend port: " PANEL_PORT

[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] ||
    die "Panel port must be numeric."

(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) ||
    die "Invalid panel port."

echo
echo "============================================================"
echo "Configuration"
echo "============================================================"
echo
echo "Domain       : $DOMAIN"
echo "WebSocket    : /ws      -> 127.0.0.1:1011"
echo "XHTTP        : /xhttp   -> 127.0.0.1:1012"
echo "gRPC         : /gprc    -> 127.0.0.1:1013"
echo "Panel        : $PANEL_PATH -> 127.0.0.1:$PANEL_PORT"
echo
read -rp "Continue? [y/N]: " ANSWER

[[ "${ANSWER,,}" =~ ^y(es)?$ ]] || exit 0

# ------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------

WEB_ROOT="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN.conf"

LE_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# ------------------------------------------------------------
# PACKAGES
# ------------------------------------------------------------

log "Installing required packages..."

apt-get update -y

apt-get install -y \
    nginx \
    certbot \
    python3-certbot-nginx \
    curl \
    git \
    ca-certificates \
    openssl

systemctl enable nginx

# ------------------------------------------------------------
# WEB ROOT
# ------------------------------------------------------------

mkdir -p "$WEB_ROOT"

# ------------------------------------------------------------
# TEMPORARY ACME CONFIG
# ------------------------------------------------------------

obtain_certificate() {

    log "Checking for existing Let's Encrypt certificate..."

    if [[ -f "$LE_CERT" && -f "$LE_KEY" ]]; then
        log "Existing Let's Encrypt certificate found."
        return
    fi

    warn "No Let's Encrypt certificate found."

    cat > /etc/nginx/sites-available/acme-bootstrap.conf <<EOF2
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

    root $WEB_ROOT;

    location ^~ /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        return 404;
    }
}
EOF2

    rm -f /etc/nginx/sites-enabled/acme-bootstrap.conf

    ln -s \
        /etc/nginx/sites-available/acme-bootstrap.conf \
        /etc/nginx/sites-enabled/acme-bootstrap.conf

    nginx -t

    systemctl restart nginx

    mkdir -p "$WEB_ROOT/.well-known/acme-challenge"

    log "Requesting Let's Encrypt certificate..."

    certbot certonly \
        --webroot \
        -w "$WEB_ROOT" \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email

    [[ -f "$LE_CERT" ]] ||
        die "Let's Encrypt certificate was not created."

    [[ -f "$LE_KEY" ]] ||
        die "Let's Encrypt private key was not created."

    rm -f /etc/nginx/sites-enabled/acme-bootstrap.conf
    rm -f /etc/nginx/sites-available/acme-bootstrap.conf
}

obtain_certificate

# ------------------------------------------------------------
# WEBSOCKET MAP
# ------------------------------------------------------------

if ! grep -q 'map \$http_upgrade \$connection_upgrade' /etc/nginx/nginx.conf; then

    log "Adding WebSocket connection map..."

    python3 <<'PY'
from pathlib import Path

path = Path("/etc/nginx/nginx.conf")
data = path.read_text()

marker = "http {"

if marker not in data:
    raise SystemExit("nginx http block not found")

insert = r'''
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

'''

data = data.replace(marker, marker + "\n" + insert, 1)

path.write_text(data)
PY

fi

# ------------------------------------------------------------
# REMOVE DEFAULT SITE
# ------------------------------------------------------------

rm -f /etc/nginx/sites-enabled/default

# ------------------------------------------------------------
# WEBSITE
# ------------------------------------------------------------

log "Creating website..."

cat > "$WEB_ROOT/index.html" <<EOF2
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$DOMAIN</title>
<style>
html,body {
    margin:0;
    min-height:100%;
    background:#111;
    color:#fff;
    font-family:Arial,sans-serif;
}

body {
    display:flex;
    align-items:center;
    justify-content:center;
    min-height:100vh;
}

main {
    max-width:700px;
    padding:40px;
    text-align:center;
}

h1 {
    font-size:42px;
}

p {
    color:#aaa;
    line-height:1.7;
}
</style>
</head>
<body>
<main>
<h1>Welcome</h1>
<p>Server successfully configured.</p>
</main>
</body>
</html>
EOF2

# ------------------------------------------------------------
# NGINX CONFIG
# ------------------------------------------------------------

log "Creating nginx configuration..."

cat > "$NGINX_CONF" <<EOF2
# ============================================================
# $DOMAIN
# Generated by nginx-xray-installer
# ============================================================

# HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $WEB_ROOT;
        try_files \$uri =404;
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}

# Reject every other HTTPS Host
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    server_name _;

    ssl_certificate     $LE_CERT;
    ssl_certificate_key $LE_KEY;

    return 404;
}

# Main domain
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $DOMAIN;

    root $WEB_ROOT;
    index index.html;

    # TLS
    ssl_certificate     $LE_CERT;
    ssl_certificate_key $LE_KEY;

    ssl_protocols TLSv1.2 TLSv1.3;

    ssl_session_cache shared:SSL:20m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # General
    keepalive_timeout 65;
    keepalive_requests 1000;

    client_max_body_size 0;

    # --------------------------------------------------------
    # WEBSOCKET
    # --------------------------------------------------------

    location = /ws {
        proxy_pass http://127.0.0.1:1011;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_buffering off;
        proxy_request_buffering off;

        proxy_connect_timeout 10s;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ^~ /ws/ {
        proxy_pass http://127.0.0.1:1011;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_buffering off;
        proxy_request_buffering off;

        proxy_connect_timeout 10s;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # --------------------------------------------------------
    # XHTTP
    # --------------------------------------------------------

    location = /xhttp {
        proxy_pass http://127.0.0.1:1012;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_set_header Connection "";

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;

        proxy_connect_timeout 10s;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ^~ /xhttp/ {
        proxy_pass http://127.0.0.1:1012;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_set_header Connection "";

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;

        proxy_connect_timeout 10s;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # --------------------------------------------------------
    # gRPC
    # --------------------------------------------------------

    location ^~ /gprc {
        grpc_pass grpc://127.0.0.1:1013;

        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;

        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
    }

    # --------------------------------------------------------
    # PANEL
    # --------------------------------------------------------

    location = $PANEL_PATH {
        proxy_pass http://127.0.0.1:$PANEL_PORT;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_buffering off;

        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ^~ $PANEL_PATH/ {
        proxy_pass http://127.0.0.1:$PANEL_PORT;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_buffering off;

        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # --------------------------------------------------------
    # WEBSITE
    # --------------------------------------------------------

    location = / {
        try_files /index.html =404;
    }

    location ~* \.(html|css|js|mjs|json|png|jpg|jpeg|gif|svg|ico|webp|woff|woff2|ttf|wasm|map)$ {
        try_files \$uri =404;

        access_log off;

        expires 7d;
        add_header Cache-Control "public";
    }

    # Everything else = 404
    location / {
        return 404;
    }
}
EOF2

# ------------------------------------------------------------
# ENABLE SITE
# ------------------------------------------------------------

rm -f "$NGINX_LINK"

ln -s "$NGINX_CONF" "$NGINX_LINK"

# ------------------------------------------------------------
# PERMISSIONS
# ------------------------------------------------------------

chown -R www-data:www-data "$WEB_ROOT"

# ------------------------------------------------------------
# TEST
# ------------------------------------------------------------

log "Testing nginx configuration..."

nginx -t

# ------------------------------------------------------------
# RELOAD
# ------------------------------------------------------------

log "Reloading nginx..."

systemctl enable nginx
systemctl restart nginx

sleep 2

systemctl is-active --quiet nginx ||
    die "nginx failed to start."

# ------------------------------------------------------------
# CERTBOT RENEWAL
# ------------------------------------------------------------

systemctl enable certbot.timer 2>/dev/null || true
systemctl start certbot.timer 2>/dev/null || true

# ------------------------------------------------------------
# COMPLETE
# ------------------------------------------------------------

echo
echo "============================================================"
echo " INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Domain:"
echo "  https://$DOMAIN/"
echo
echo "WebSocket:"
echo "  /ws -> 127.0.0.1:1011"
echo
echo "XHTTP:"
echo "  /xhttp -> 127.0.0.1:1012"
echo
echo "gRPC:"
echo "  /gprc -> 127.0.0.1:1013"
echo
echo "Panel:"
echo "  $PANEL_PATH -> 127.0.0.1:$PANEL_PORT"
echo
echo "HTTP -> HTTPS: ENABLED"
echo "HTTP/2:         ENABLED"
echo "Unknown Hosts:  404"
echo "Unknown Paths:  404"
echo
echo "============================================================"
