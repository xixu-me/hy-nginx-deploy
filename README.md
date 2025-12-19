# HY Nginx Deploy

One-command automated deployment script for setting up a HY proxy server with nginx and SSL certificates on Debian/Ubuntu systems.

## Features

- 🚀 **One-Command Setup**: Fully automated installation and configuration
- 🔒 **Automatic SSL**: Let's Encrypt certificate management via Certbot
- 🌐 **Nginx Integration**: Professional masquerade website on port 443/TCP
- 🛡️ **Security Hardened**: UFW firewall configuration and system tuning
- 🔐 **Auto-Generated Passwords**: Secure random password generation
- 📝 **Ready-to-Use Config**: Outputs client configuration

## Quick Start

```bash
sudo bash -c "$(curl -fsSL https://github.com/xixu-me/hy-nginx-deploy/raw/refs/heads/main/install.sh)" -s -d example.com -e admin@example.com
```

Replace `example.com` with your domain and `admin@example.com` with your email.

## Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+ (x86_64)
- **Domain**: A domain name pointed to your server's IP address
- **Root Access**: Script must be run with sudo/root privileges
- **Ports**: 22 (SSH), 80 (HTTP), 443/TCP (HTTPS), 443/UDP (HY)

## Installation

### Method 1: Direct Download

```bash
curl -fsSL https://raw.githubusercontent.com/xixu-me/hy-nginx-deploy/main/install.sh -o install.sh
sudo bash install.sh -d your-domain.com -e your@email.com
```

### Method 2: Clone Repository

```bash
git clone https://github.com/xixu-me/hy-nginx-deploy.git
cd hy-nginx-deploy
sudo bash install.sh -d your-domain.com -e your@email.com
```

## Usage

```
sudo bash install.sh -d <domain> -e <email> [-p <password>] [--no-ufw] [--no-sysctl]

Options:
  -d, --domain     Domain name (required)
  -e, --email      Email for Let's Encrypt registration (required)
  -p, --password   HY password (optional; auto-generated if omitted)
  --no-ufw         Do not enable/modify UFW firewall
  --no-sysctl      Do not apply sysctl tuning for UDP buffers
  -h, --help       Show help message
```

### Examples

**Basic installation with auto-generated password:**

```bash
sudo bash install.sh -d proxy.example.com -e admin@example.com
```

**Custom password:**

```bash
sudo bash install.sh -d proxy.example.com -e admin@example.com -p MySecurePass123
```

**Skip firewall configuration:**

```bash
sudo bash install.sh -d proxy.example.com -e admin@example.com --no-ufw
```

## What Gets Installed

The script automatically sets up:

1. **Nginx Web Server**
   - Serves a masquerade website on port 443/TCP
   - SSL/TLS termination via Let's Encrypt
   - Automatic certificate renewal

2. **HY Server**
   - Listens on port 443/UDP
   - Password authentication
   - SSL certificates from Let's Encrypt
   - Masquerades as HTTPS traffic to nginx

3. **SSL Certificates**
   - Let's Encrypt certificates via Certbot
   - Automatic HTTPS redirect
   - Shared between nginx and HY

4. **Firewall (UFW)**
   - Port 22 (SSH)
   - Port 80 (HTTP)
   - Port 443/TCP (HTTPS)
   - Port 443/UDP (HY)

5. **System Tuning**
   - UDP buffer optimization for better performance

## Client Configuration

After installation, the script outputs a ready-to-use configuration:

```yaml
proxies:
  - name: "hy2-your-domain.com"
    type: hysteria2
    server: your-domain.com
    port: 443
    password: "your-generated-password"
    skip-cert-verify: false
    alpn:
      - h3
```

Copy this configuration to your client.

## Management

### Check Service Status

```bash
# Nginx
systemctl status nginx

# HY
systemctl status hysteria-server.service
```

### View Logs

```bash
# Nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# HY
journalctl -u hysteria-server.service -f
```

### Restart Services

```bash
# Nginx
systemctl restart nginx

# HY
systemctl restart hysteria-server.service
```

### Certificate Renewal

Certificates are automatically renewed by Certbot. To manually renew:

```bash
certbot renew
systemctl reload nginx
systemctl restart hysteria-server.service
```

## Configuration Files

- **Nginx**: `/etc/nginx/sites-available/your-domain.com`
- **HY**: `/etc/hysteria/config.yaml`
- **Web Root**: `/var/www/your-domain.com`
- **SSL Certificates**: `/etc/letsencrypt/live/your-domain.com/`

## Troubleshooting

### Domain Not Resolving

Ensure your domain's DNS A record points to your server's IP:

```bash
dig +short your-domain.com
```

### Certbot Fails

- Verify domain DNS is correctly configured
- Check ports 80 and 443/TCP are accessible
- Ensure no other web server is running

### HY Connection Issues

```bash
# Check service status
systemctl status hysteria-server.service

# View detailed logs
journalctl -u hysteria-server.service -n 50

# Test UDP port
nc -vzu your-ip 443
```

### Firewall Blocking Traffic

```bash
# Check UFW status
ufw status verbose

# Allow required ports
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
```

## Security Considerations

- The script generates cryptographically secure random passwords
- All traffic is encrypted with TLS 1.3
- Consider using a strong custom password with `-p` option
- Regularly update the system: `apt update && apt upgrade`
- Monitor logs for suspicious activity

## Uninstallation

```bash
# Stop and disable services
systemctl stop hysteria-server.service nginx
systemctl disable hysteria-server.service nginx

# Remove packages
apt remove --purge nginx certbot python3-certbot-nginx

# Remove configurations
rm -rf /etc/hysteria /etc/nginx /var/www/your-domain.com
rm -rf /etc/letsencrypt

# Remove HY binary
rm -f /usr/local/bin/hysteria
```

## License

[MIT License](LICENSE)

## Disclaimer

This tool is for educational and legitimate use only. Users are responsible for complying with local laws and regulations. The authors are not responsible for any misuse or damage caused by this software.
