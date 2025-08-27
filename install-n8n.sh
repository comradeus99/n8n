#!/bin/bash

# Kiểm tra xem script có được chạy với quyền root không
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận input domain từ người dùng
read -p "Enter your domain or subdomain: " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Sử dụng thư mục /home trực tiếp
N8N_DIR="/home/n8n"

# Cài đặt Docker và Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR

# Tạo file docker-compose.yml
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_SECURE_COOKIE=true
      - N8N_LOG_LEVEL=info
    volumes:
      - $N8N_DIR/.n8n:/home/node/.n8n
    networks:
      - n8n_network
    dns:
      - 8.8.8.8
      - 1.1.1.1
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  caddy:
    image: caddy:2-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  caddy_data:
    external: false
  caddy_config:
    external: false
EOF

# Tạo file Caddyfile với cấu hình bảo mật tốt hơn
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678 {
        health_uri /healthz
        health_interval 30s
        health_timeout 10s
    }
    
    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https: wss:;"
    }
    
    # Compress responses
    encode gzip
    
    # Log access
    log {
        output file /var/log/caddy/access.log
    }
}
EOF

# Tạo thư mục .n8n với quyền phù hợp
mkdir -p $N8N_DIR/.n8n

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động các container
cd $N8N_DIR
docker compose up -d

# Đợi một chút để containers khởi động
echo "Waiting for containers to start..."
sleep 10

# Kiểm tra trạng thái containers
if docker compose ps | grep -q "Up"; then
    echo ""
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║                                                             ║"
    echo "║  ✅ N8n đã được cài đặt thành công!                         ║"
    echo "║                                                             ║"
    echo "║  🌐 Truy cập: https://${DOMAIN}                             ║"
    echo "║                                                             ║"
    echo "║  📚 Học n8n cơ bản: https://n8n-basic.mecode.pro            ║"
    echo "║                                                             ║"
    echo "║  🔧 Quản lý containers:                                     ║"
    echo "║     - Xem logs: docker compose logs -f                     ║"
    echo "║     - Restart: docker compose restart                      ║"
    echo "║     - Stop: docker compose down                            ║"
    echo "║                                                             ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo ""
else
    echo "❌ Có lỗi xảy ra khi khởi động containers. Kiểm tra logs:"
    docker compose logs
fi
