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

# Cài đặt Docker và Docker Compose (phiên bản mới)
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

# Cài đặt Docker (sử dụng script chính thức từ Docker)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Cài đặt Docker Compose v2 (plugin)
mkdir -p ~/.docker/cli-plugins/
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose

# Khởi động Docker service
systemctl enable docker
systemctl start docker

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR

# Pull phiên bản n8n mới nhất
echo "Pulling latest n8n Docker image..."
docker pull n8nio/n8n:latest

# Tạo file docker-compose.yml với cấu hình tối ưu
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_METRICS=false
      - N8N_SECURE_COOKIE=true
      - N8N_PERSONALIZATION_ENABLED=false
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n_network
    dns:
      - 8.8.8.8
      - 1.1.1.1
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      n8n:
        condition: service_healthy
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  n8n_data:
    driver: local
  caddy_data:
    driver: local
  caddy_config:
    driver: local
EOF

# Tạo file Caddyfile với cấu hình bảo mật tốt hơn
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    # Bảo mật headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }
    
    # Tự động HTTPS
    tls {
        protocols tls1.2 tls1.3
    }
    
    # Ghi log
    log {
        output file /var/log/caddy/${DOMAIN}.log {
            roll_size 100mb
            roll_keep 5
        }
    }
}
EOF

# Tạo thư mục log cho Caddy
mkdir -p /var/log/caddy

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động các container
cd $N8N_DIR
docker compose up -d

# Kiểm tra trạng thái
echo "Waiting for services to start..."
sleep 30

# Hiển thị trạng thái
docker compose ps

echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             "
echo "║  ✅ N8n đã được cài đặt thành công!                         "
echo "║                                                             "
echo "║  🌐 Truy cập: https://${DOMAIN}                             "
echo "║                                                             "
echo "║  📊 Kiểm tra logs: docker compose logs -f                   "
echo "║  🔄 Restart: docker compose restart                         "
echo "║  ⏹️ Stop: docker compose down                               "
echo "║                                                             "
echo "║  📚 Học n8n cơ bản: https://n8n-basic.mecode.pro            "
echo "║                                                             "
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""

# Hướng dẫn cập nhật
cat << EOF

🔄 HƯỚNG DẪN CẬP NHẬT N8N:
========================================
Để cập nhật n8n lên phiên bản mới nhất:

cd $N8N_DIR
docker compose pull
docker compose up -d

Kiểm tra phiên bản hiện tại:
docker compose exec n8n n8n --version

EOF
