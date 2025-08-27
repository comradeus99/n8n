#!/bin/bash

# N8N Management Script with Update, Backup & Restore functions
# Usage: ./n8n-manager.sh [install|update|backup|restore|status]

N8N_DIR="/home/n8n"
BACKUP_DIR="/home/n8n-backups"
SCRIPT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} N8N Manager v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script needs to be run with root privileges"
        exit 1
    fi
}

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

# Cài đặt N8N lần đầu
install_n8n() {
    print_header
    print_status "Starting N8N installation..."

    # Nhận input domain từ người dùng
    read -p "Enter your domain or subdomain: " DOMAIN

    # Kiểm tra domain
    if check_domain $DOMAIN; then
        print_status "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
    else
        print_error "Domain $DOMAIN has not been pointed to this server."
        print_warning "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
        print_warning "After updating the DNS, run this script again"
        exit 1
    fi

    # Cài đặt Docker và Docker Compose
    print_status "Installing Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

    # Cài đặt Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh

    # Cài đặt Docker Compose v2
    mkdir -p ~/.docker/cli-plugins/
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose

    # Khởi động Docker service
    systemctl enable docker
    systemctl start docker

    # Tạo thư mục
    mkdir -p $N8N_DIR
    mkdir -p $BACKUP_DIR

    create_docker_compose $DOMAIN
    create_caddyfile $DOMAIN
    
    # Pull image và start
    print_status "Pulling latest n8n Docker image..."
    docker pull n8nio/n8n:latest

    # Set permissions
    chown -R 1000:1000 $N8N_DIR
    chmod -R 755 $N8N_DIR

    # Start containers
    cd $N8N_DIR
    docker compose up -d

    print_status "Waiting for services to start..."
    sleep 30

    show_status
    show_success_message $DOMAIN
}

# Tạo file docker-compose.yml
create_docker_compose() {
    local domain=$1
    cat << EOF > $N8N_DIR/docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - N8N_HOST=${domain}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${domain}
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
}

# Tạo Caddyfile
create_caddyfile() {
    local domain=$1
    cat << EOF > $N8N_DIR/Caddyfile
${domain} {
    reverse_proxy n8n:5678 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }
    
    tls {
        protocols tls1.2 tls1.3
    }
    
    log {
        output file /var/log/caddy/${domain}.log {
            roll_size 100mb
            roll_keep 5
        }
    }
}
EOF
    mkdir -p /var/log/caddy
}

# Update N8N - 1 câu lệnh
update_n8n() {
    print_header
    print_status "Starting N8N update process..."

    if [ ! -d "$N8N_DIR" ]; then
        print_error "N8N installation not found. Please install first."
        exit 1
    fi

    cd $N8N_DIR

    # Tạo backup trước khi update
    print_status "Creating backup before update..."
    local backup_name="pre-update-$(date +%Y%m%d-%H%M%S)"
    backup_n8n $backup_name

    # Stop containers
    print_status "Stopping N8N containers..."
    docker compose down

    # Pull latest images
    print_status "Pulling latest images..."
    docker compose pull

    # Start containers
    print_status "Starting updated containers..."
    docker compose up -d

    print_status "Waiting for services to start..."
    sleep 30

    show_status
    print_status "✅ N8N has been successfully updated!"
    print_status "📁 Pre-update backup saved as: $backup_name"
    print_status "🔍 Check logs: docker compose logs -f"
}

# Backup N8N data
backup_n8n() {
    local backup_name=${1:-"backup-$(date +%Y%m%d-%H%M%S)"}
    local backup_path="$BACKUP_DIR/$backup_name"
    
    print_header
    print_status "Creating backup: $backup_name"

    if [ ! -d "$N8N_DIR" ]; then
        print_error "N8N installation not found."
        exit 1
    fi

    mkdir -p $backup_path

    cd $N8N_DIR

    # Export volumes
    print_status "Backing up N8N data volume..."
    docker run --rm \
        -v n8n_n8n_data:/source:ro \
        -v $backup_path:/backup \
        alpine:latest \
        tar czf /backup/n8n_data.tar.gz -C /source .

    print_status "Backing up Caddy data..."
    docker run --rm \
        -v n8n_caddy_data:/source:ro \
        -v $backup_path:/backup \
        alpine:latest \
        tar czf /backup/caddy_data.tar.gz -C /source .

    # Copy config files
    print_status "Backing up configuration files..."
    cp docker-compose.yml $backup_path/
    cp Caddyfile $backup_path/

    # Create backup info
    cat << EOF > $backup_path/backup_info.txt
Backup created: $(date)
N8N Version: $(docker compose exec -T n8n n8n --version 2>/dev/null || echo "N/A")
Server IP: $(curl -s https://api.ipify.org)
Backup Path: $backup_path
EOF

    print_status "✅ Backup completed successfully!"
    print_status "📁 Backup location: $backup_path"
    print_status "📋 Files included:"
    ls -la $backup_path
}

# Restore N8N từ backup
restore_n8n() {
    print_header
    print_status "N8N Restore Process"

    # List available backups
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR)" ]; then
        print_error "No backups found in $BACKUP_DIR"
        exit 1
    fi

    print_status "Available backups:"
    ls -la $BACKUP_DIR/

    read -p "Enter backup name to restore: " BACKUP_NAME
    local restore_path="$BACKUP_DIR/$BACKUP_NAME"

    if [ ! -d "$restore_path" ]; then
        print_error "Backup not found: $restore_path"
        exit 1
    fi

    # Get domain for new installation
    read -p "Enter domain for this server: " DOMAIN

    # Kiểm tra domain
    if ! check_domain $DOMAIN; then
        print_warning "Domain $DOMAIN is not pointing to this server."
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Stop existing containers if any
    if [ -d "$N8N_DIR" ]; then
        print_status "Stopping existing N8N containers..."
        cd $N8N_DIR
        docker compose down 2>/dev/null || true
    fi

    # Create directories
    mkdir -p $N8N_DIR

    # Restore config files
    print_status "Restoring configuration files..."
    cp $restore_path/docker-compose.yml $N8N_DIR/
    
    # Update domain in Caddyfile if different
    if [ -f "$restore_path/Caddyfile" ]; then
        sed "s/^[^{]*{/${DOMAIN} {/" $restore_path/Caddyfile > $N8N_DIR/Caddyfile
    else
        create_caddyfile $DOMAIN
    fi

    # Create and start containers to create volumes
    cd $N8N_DIR
    docker compose up -d
    sleep 10
    docker compose down

    # Restore data volumes
    print_status "Restoring N8N data..."
    docker run --rm \
        -v n8n_n8n_data:/target \
        -v $restore_path:/backup:ro \
        alpine:latest \
        sh -c "cd /target && tar xzf /backup/n8n_data.tar.gz"

    print_status "Restoring Caddy data..."
    docker run --rm \
        -v n8n_caddy_data:/target \
        -v $restore_path:/backup:ro \
        alpine:latest \
        sh -c "cd /target && tar xzf /backup/caddy_data.tar.gz"

    # Set permissions
    chown -R 1000:1000 $N8N_DIR
    chmod -R 755 $N8N_DIR

    # Start containers
    print_status "Starting N8N containers..."
    docker compose up -d

    print_status "Waiting for services to start..."
    sleep 30

    show_status
    print_status "✅ N8N has been successfully restored!"
    print_status "🌐 Access: https://$DOMAIN"
    print_status "📋 Restored from: $restore_path"
}

# Hiển thị trạng thái
show_status() {
    print_status "Current container status:"
    if [ -d "$N8N_DIR" ]; then
        cd $N8N_DIR
        docker compose ps
    else
        print_warning "N8N not installed"
    fi
}

# Hiển thị thông báo thành công
show_success_message() {
    local domain=$1
    echo ""
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║  ✅ N8n đã được cài đặt thành công!                         ║"
    echo "║                                                             ║"
    echo "║  🌐 Truy cập: https://${domain}                             ║"
    echo "║                                                             ║"
    echo "║  📊 Kiểm tra logs: docker compose logs -f                   ║"
    echo "║  🔄 Restart: docker compose restart                         ║"
    echo "║  ⏹️ Stop: docker compose down                               ║"
    echo "║                                                             ║"
    echo "║  📚 Học n8n cơ bản: https://n8n-basic.mecode.pro            ║"
    echo "║                                                             ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
}

# Hiển thị hướng dẫn sử dụng
show_usage() {
    print_header
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install   - Install N8N for the first time"
    echo "  update    - Update N8N to latest version (1 command)"
    echo "  backup    - Create backup of N8N data (1 command)"
    echo "  restore   - Restore N8N from backup (1 command)"
    echo "  status    - Show current status"
    echo ""
    echo "Examples:"
    echo "  $0 install          # First installation"
    echo "  $0 update           # Update to latest version"
    echo "  $0 backup           # Create backup"
    echo "  $0 restore          # Restore from backup"
    echo ""
}

# Main script logic
main() {
    case "${1:-}" in
        "install")
            check_root
            install_n8n
            ;;
        "update")
            check_root
            update_n8n
            ;;
        "backup")
            check_root
            backup_n8n
            ;;
        "restore")
            check_root
            restore_n8n
            ;;
        "status")
            show_status
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"
