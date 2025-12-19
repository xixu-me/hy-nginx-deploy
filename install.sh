#!/usr/bin/env bash
set -euo pipefail

# Constants
DOMAIN=""
EMAIL=""
HY_PASS=""
NO_UFW=0
NO_SYSCTL=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+] $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}" >&2; }
err() { echo -e "${RED}[✗] $*${NC}" >&2; exit 1; }

need_root() {
    [[ "${EUID}" -eq 0 ]] || err "Please run as root: sudo bash $0 ..."
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "${ID}" != "ubuntu" && "${ID}" != "debian" ]]; then
            warn "This script is optimized for Debian/Ubuntu. Your OS (${ID}) might not be supported."
            read -r -p "Press ENTER to continue anyway, or Ctrl+C to abort..."
        fi
    else
        err "Cannot detect OS. /etc/os-release not found."
    fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<EOF
Usage:
  sudo bash $0 -d <domain> -e <email> [-p <password>] [--no-ufw] [--no-sysctl]

Options:
  -d, --domain     Domain name (required)
  -e, --email      Email for Let's Encrypt registration (required)
  -p, --password   HY password (optional; auto-generated if omitted)
  --no-ufw         Do not enable/modify UFW (firewall)
  --no-sysctl      Do not apply sysctl tuning (UDP buffers)
  -h, --help       Show this help message

Example:
  sudo bash $0 -d example.com -e admin@example.com
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain) DOMAIN="${2:-}"; shift 2;;
            -e|--email) EMAIL="${2:-}"; shift 2;;
            -p|--password) HY_PASS="${2:-}"; shift 2;;
            --no-ufw) NO_UFW=1; shift 1;;
            --no-sysctl) NO_SYSCTL=1; shift 1;;
            -h|--help) usage; exit 0;;
            *) err "Unknown argument: $1 (use -h for help)";;
        esac
    done
    
    # Interactive prompts if missing args
    if [[ -z "${DOMAIN}" ]]; then
        read -r -p "Enter your domain (e.g., example.com): " DOMAIN
    fi
    if [[ -z "${EMAIL}" ]]; then
        read -r -p "Enter your email for Let's Encrypt: " EMAIL
    fi
    
    # Generate password if missing
    if [[ -z "${HY_PASS}" ]]; then
        if has_cmd openssl; then
            HY_PASS="$(openssl rand -base64 24 | tr -d '\n')"
        else
            HY_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        fi
    fi
    
    # Validations
    [[ "${DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]] || err "Invalid domain format: ${DOMAIN}"
    [[ "${EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || warn "Email looks simple, but proceeding: ${EMAIL}"
}

apt_install() {
    log "Updating system and installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl ca-certificates gnupg lsb-release \
    nginx \
    certbot python3-certbot-nginx \
    ufw
    
    systemctl enable --now nginx
}

setup_nginx_site() {
    log "Configuring nginx site for ${DOMAIN}..."
    local webroot="/var/www/${DOMAIN}"
    mkdir -p "${webroot}"
    
    # Create a nice masquerade page
    cat > "${webroot}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to ${DOMAIN}</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background-color: #f0f2f5; color: #1c1e21; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .container { text-align: center; padding: 2rem; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { margin-bottom: 0.5rem; }
        p { color: #606770; }
    </style>
</head>
<body>
    <div class="container">
        <h1>${DOMAIN}</h1>
        <p>Site is under construction.</p>
    </div>
</body>
</html>
EOF
    chown -R www-data:www-data "${webroot}"
    
    local site_avail="/etc/nginx/sites-available/${DOMAIN}"
    if [[ -f "${site_avail}" ]]; then
        cp -a "${site_avail}" "${site_avail}.$(date +%F_%H%M%S).bak"
        warn "Existing nginx config found. Backed up to ${site_avail}.bak"
    fi
    
    cat > "${site_avail}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${webroot};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    ln -sf "${site_avail}" "/etc/nginx/sites-enabled/${DOMAIN}"
    rm -f /etc/nginx/sites-enabled/default || true
    
    nginx -t
    systemctl reload nginx
}

issue_cert() {
    log "Issuing SSL certificate via Certbot..."
    if ! certbot --nginx -d "${DOMAIN}" \
    -m "${EMAIL}" --agree-tos --redirect --non-interactive --no-eff-email; then
        err "Certbot failed. Check your DNS and firewall settings.\nEnsure ${DOMAIN} points to valid IP: $(curl -s ifconfig.me)"
    fi
    
    nginx -t
    systemctl reload nginx
}

install_hy() {
    log "Installing HY..."
    # Always get latest
    HYSTERIA_USER=root bash <(curl -fsSL https://get.hy2.sh/)
}

configure_hy() {
    log "Configuring HY..."
    local cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    local key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    
    [[ -f "${cert}" ]] || err "Certificate not found: ${cert}"
    [[ -f "${key}"  ]] || err "Private key not found: ${key}"
    
    mkdir -p /etc/hysteria
    
    # HY Config
    # Uses UDP/443. Nginx handles TCP/443.
    cat > /etc/hysteria/config.yaml <<EOF
listen: :443

tls:
  cert: ${cert}
  key: ${key}

auth:
  type: password
  password: "${HY_PASS}"

masquerade:
  type: proxy
  proxy:
    url: https://${DOMAIN}/
    rewriteHost: true
EOF
    
    systemctl enable --now hysteria-server.service
    systemctl restart hysteria-server.service
}

tune_sysctl() {
    [[ "${NO_SYSCTL}" -eq 1 ]] && { warn "Skipping sysctl tuning."; return 0; }
    log "Applying UDP buffer tuning..."
    
    cat > /etc/sysctl.d/99-hy.conf <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
    sysctl --system >/dev/null
}

setup_ufw() {
    [[ "${NO_UFW}" -eq 1 ]] && { warn "Skipping UFW setup."; return 0; }
    
    log "Configuring UFW firewall..."
    ufw allow 22/tcp  # SSH
    ufw allow 80/tcp  # HTTP
    ufw allow 443/tcp # HTTPS
    ufw allow 443/udp # HY (QUIC)
    
    if ufw status | grep -qi "inactive"; then
        echo "y" | ufw enable >/dev/null || true
    fi
}

print_proxies() {
    echo
    echo "========== Client Config Snippet =========="
    cat <<EOF
proxies:
  - name: "hy2-${DOMAIN}"
    type: hysteria2
    server: ${DOMAIN}
    port: 443
    password: "${HY_PASS}"
    skip-cert-verify: false
    alpn:
      - h3
EOF
}

verify() {
    log "Installation Complete! Verifying services..."
    
    echo "------------------------------------------------"
    echo " Nginx Status: $(systemctl is-active nginx)"
    echo " HY Status: $(systemctl is-active hysteria-server.service)"
    echo "------------------------------------------------"
    
    print_proxies
    
    echo
    echo "Logs: journalctl -u hysteria-server.service -f"
    echo "Enjoy!"
}

main() {
    need_root
    check_os
    parse_args "$@"
    apt_install
    setup_nginx_site
    issue_cert
    install_hy
    tune_sysctl
    configure_hy
    setup_ufw
    verify
}

main "$@"
