# Nginx Xray Installer

Automated Debian/Ubuntu installer for:

- Nginx
- Let's Encrypt TLS
- HTTP → HTTPS redirection
- HTTP/2
- WebSocket reverse proxy
- XHTTP reverse proxy
- gRPC reverse proxy
- Panel reverse proxy
- Strict Host handling
- 404 handling for unknown paths
- Long-lived proxy connections

## Architecture

| Path | Backend |
|---|---|
| `/ws` | `127.0.0.1:1011` |
| `/xhttp` | `127.0.0.1:1012` |
| `/gprc` | `127.0.0.1:1013` |
| User-selected panel path | User-selected port |
| `/` | `/var/www/<domain>` |

## Requirements

- Debian or Ubuntu
- Root access
- A domain pointing to the VPS
- TCP 80 accessible for Let's Encrypt
- TCP 443 accessible for HTTPS

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/nginx-xray-installer.git
cd nginx-xray-installer
chmod +x setup.sh
sudo ./setup.sh


cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
