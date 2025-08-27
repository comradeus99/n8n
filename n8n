#!/bin/bash

# N8N One-Line Installer & Updater
# Usage: 
#   Fresh install: curl -fsSL https://your-domain.com/install-n8n.sh | bash
#   Update: curl -fsSL https://your-domain.com/install-n8n.sh | bash -s -- --update
#   Update with domain: curl -fsSL https://your-domain.com/install-n8n.sh | bash -s -- --update --domain=your-domain.com

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTION="install"
DOMAIN=""
N8N_DIR="/home/n8n"
UPDATE_ONLY=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --update)
            ACTION="update"
            UPDATE_ONLY=true
            shift
            ;;
        --domain=*)
            DOMAIN="${arg#*=}"
            shift
            ;;
        --help|-h)
            echo "N8N Installer & Updater"
            echo ""
            echo "Usage:"
            echo "  Fresh install: $0"
            echo "  Update only:   $0 --update"
            echo "  Update with domain: $0 --update --domain=your-domain.com"
            echo ""
            echo "One-line usage:"
            echo "  curl -fsSL https://your-script-url.sh | bash"
            echo "  curl -fsSL https://your-script-url.sh | bash -s -- --update"
            echo "  curl -fsSL https://your-script-url.sh | bash -s -- --update --domain=example.com"
            exit 0
            ;;
    esac
done

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script needs to be run with root privileges"
        print_status "Please run: sudo $0"
        exit 1
    fi
}

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0
    else
        return 1
    fi
}

# Hàm lấy domain từ cấu hình hiện tại
get_existing_domain() {
    if [ -f "$N8N_DIR/docker-compose.yml" ]; then
        DOMAIN=$(grep "N8N_HOST=" "$N8N_DIR/docker-compose.yml" | cut -d'=' -f2 | tr -d '"' | head -1)
        if [ -n "$DOMAIN" ]; then
            print_status "Found existing domain: $DOMAIN"
        fi
    fi
}

# Hàm nhập domain
input_domain() {
    if [ -z "$DOMAIN" ]; then
        echo ""
        read -p "Enter your domain or subdomain: " DOMAIN
    fi
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain cannot be empty!"
        exit 1
    fi
}

# Hàm cài đặt Docker
install_docker() {
    print_status "Installing Docker and Docker Compose..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update and install prerequisites
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
    
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker service
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed successfully!"
}

# Hàm tạo cấu hình n8n
create_n8n_config() {
    print_status "Creating N8N configuration..."
    
    # Create directory
    mkdir -p $N8N_DIR/.n8n
    
    # Create docker-compose.yml
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
      - N8N_METRICS=false
    volumes:
      - \${PWD}/.n8n:/home/node/.n8n
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
      - \${PWD}/Caddyfile:/etc/caddy/Caddyfile
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
  caddy_config:
EOF

    # Create Caddyfile
    cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678 {
        health_uri /healthz
        health_interval 30s
        health_timeout 10s
    }
    
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
    
    encode gzip
}
EOF

    # Set permissions
    chown -R 1000:1000 $N8N_DIR
    chmod -R 755 $N8N_DIR
    
    print_success "Configuration created!"
}

# Hàm update n8n
update_n8n() {
    print_status "Updating N8N to latest version..."
    
    cd $N8N_DIR
    
    # Pull latest images
    docker compose pull
    
    # Restart containers
    docker compose up -d
    
    print_success "N8N updated successfully!"
}

# Hàm cài đặt mới
fresh_install() {
    print_status "Starting fresh N8N installation..."
    
    # Get domain input
    input_domain
    
    # Check domain
    if check_domain $DOMAIN; then
        print_success "Domain $DOMAIN is correctly pointed to this server"
    else
        print_warning "Domain $DOMAIN is not pointed to this server"
        print_status "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
        read -p "Continue anyway? (y/N): " continue_install
        if [[ ! $continue_install =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled"
            exit 1
        fi
    fi
    
    # Install Docker if not exists
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        print_status "Docker is already installed"
    fi
    
    # Create configuration
    create_n8n_config
    
    # Start containers
    cd $N8N_DIR
    docker compose up -d
}

# Hàm tạo script update nhanh
create_update_script() {
    cat << 'EOF' > /usr/local/bin/n8n-update
#!/bin/bash
cd /home/n8n
docker compose pull
docker compose up -d
echo "✅ N8N updated to latest version!"
EOF
    chmod +x /usr/local/bin/n8n-update
    print_success "Created quick update command: n8n-update"
}

# Main execution
main() {
    print_status "N8N Installer & Updater"
    echo "========================"
    
    # Check root privileges
    check_root
    
    if [ "$UPDATE_ONLY" = true ]; then
        # Update mode
        if [ ! -d "$N8N_DIR" ]; then
            print_error "N8N installation not found at $N8N_DIR"
            print_status "Run without --update flag for fresh installation"
            exit 1
        fi
        
        # Get existing domain if not provided
        if [ -z "$DOMAIN" ]; then
            get_existing_domain
        fi
        
        # Update domain in config if provided
        if [ -n "$DOMAIN" ]; then
            print_status "Updating domain to: $DOMAIN"
            sed -i "s/N8N_HOST=.*/N8N_HOST=${DOMAIN}/" "$N8N_DIR/docker-compose.yml"
            sed -i "s/WEBHOOK_URL=.*/WEBHOOK_URL=https:\/\/${DOMAIN}/" "$N8N_DIR/docker-compose.yml"
            sed -i "1s/.*/${DOMAIN} {/" "$N8N_DIR/Caddyfile"
        fi
        
        update_n8n
    else
        # Fresh install mode
        if [ -d "$N8N_DIR" ] && [ -f "$N8N_DIR/docker-compose.yml" ]; then
            print_warning "Existing N8N installation found!"
            read -p "Do you want to update instead? (Y/n): " update_choice
            if [[ ! $update_choice =~ ^[Nn]$ ]]; then
                ACTION="update"
                UPDATE_ONLY=true
                get_existing_domain
                update_n8n
            else
                fresh_install
            fi
        else
            fresh_install
        fi
    fi
    
    # Create quick update script
    create_update_script
    
    # Wait for containers
    if [ "$ACTION" = "install" ] || [ "$UPDATE_ONLY" = false ]; then
        print_status "Waiting for containers to start..."
        sleep 15
    fi
    
    # Check status
    cd $N8N_DIR
    if docker compose ps | grep -q "Up"; then
        echo ""
        echo "╔═════════════════════════════════════════════════════════════╗"
        echo "║                                                             ║"
        echo "║  ✅ N8n is running successfully!                            ║"
        echo "║                                                             ║"
        if [ -n "$DOMAIN" ]; then
            echo "║  🌐 Access: https://${DOMAIN}                               ║"
        fi
        echo "║                                                             ║"
        echo "║  📚 Learn N8N: https://n8n-basic.mecode.pro                 ║"
        echo "║                                                             ║"
        echo "║  🔧 Quick Commands:                                         ║"
        echo "║     • Update: n8n-update                                   ║"
        echo "║     • Logs: cd /home/n8n && docker compose logs -f        ║"
        echo "║     • Restart: cd /home/n8n && docker compose restart     ║"
        echo "║                                                             ║"
        echo "╚═════════════════════════════════════════════════════════════╝"
        echo ""
    else
        print_error "Some containers failed to start. Check logs:"
        docker compose logs --tail=50
    fi
}

# Run main function
main "$@"
