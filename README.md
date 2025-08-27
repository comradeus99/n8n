curl -sSL https://raw.githubusercontent.com/comradeus99/n8n/refs/heads/main/install-n8n.sh > i.sh && sudo bash i.sh

# TỔNG HỢP LỆNH N8N - HƯỚNG DẪN ĐẦY ĐỦ

## 1. KIỂM TRA PHIÊN BẢN N8N

### Kiểm tra phiên bản hiện tại
```bash
# Cách 1: Từ container đang chạy
docker exec -it n8n_n8n_1 n8n --version

# Cách 2: Sử dụng docker-compose
cd /home/n8n
docker-compose exec n8n n8n --version

# Cách 3: Tìm container name trước
docker ps | grep n8n
docker exec -it <container_name> n8n --version

# Cách 4: Kiểm tra image version
docker images | grep n8n
```

### Kiểm tra phiên bản mới nhất
```bash
# Từ Docker Hub
curl -s "https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags/?page_size=10" | jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1

# Từ GitHub API
curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | jq -r '.tag_name'

# Script kiểm tra đầy đủ
#!/bin/bash
echo "🔍 Đang kiểm tra phiên bản n8n..."
echo "📦 Phiên bản hiện tại:"
cd /home/n8n && docker-compose exec -T n8n n8n --version 2>/dev/null || echo "Không thể kiểm tra"
echo "🚀 Phiên bản mới nhất:"
LATEST_VERSION=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | jq -r '.tag_name')
echo "n8n@${LATEST_VERSION}"
```

## 2. QUẢN LÝ DOCKER VÀ DOCKER-COMPOSE

### Cài đặt Docker và Docker Compose
```bash
# Cập nhật hệ thống
apt-get update

# Cài đặt Docker
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Khởi động Docker
systemctl start docker
systemctl enable docker

# Kiểm tra cài đặt
docker --version
docker compose version
```

### Kiểm tra Docker
```bash
# Kiểm tra trạng thái Docker
systemctl status docker

# Kiểm tra version
docker --version
docker-compose --version
docker compose version

# Kiểm tra containers đang chạy
docker ps

# Kiểm tra tất cả containers
docker ps -a

# Kiểm tra images
docker images
```

## 3. QUẢN LÝ N8N CONTAINER

### Khởi động và dừng N8N
```bash
# Di chuyển đến thư mục n8n
cd /home/n8n

# Khởi động containers
docker-compose up -d

# Dừng containers
docker-compose down

# Restart containers
docker-compose restart

# Xem logs
docker-compose logs
docker-compose logs -f  # Theo dõi real-time
docker-compose logs n8n  # Chỉ logs của n8n
```

### Kiểm tra trạng thái
```bash
# Xem trạng thái containers
docker-compose ps

# Xem chi tiết containers
docker-compose top

# Kiểm tra resource usage
docker stats
```

## 4. CẬP NHẬT N8N

### Cập nhật lên phiên bản mới nhất
```bash
# Backup trước khi cập nhật
cp -r /home/n8n /home/n8n-backup-$(date +%Y%m%d)

# Cập nhật images
cd /home/n8n
docker-compose pull

# Restart với image mới
docker-compose down
docker-compose up -d

# Hoặc lệnh ngắn gọn
cd /home/n8n && docker-compose pull && docker-compose up -d
```

### Cập nhật phiên bản cụ thể
```bash
# Sửa docker-compose.yml
nano /home/n8n/docker-compose.yml
# Thay đổi: image: n8nio/n8n:latest thành image: n8nio/n8n:1.x.x

# Sau đó cập nhật
docker-compose pull
docker-compose up -d
```

## 5. BACKUP VÀ RESTORE

### Backup N8N
```bash
# Backup toàn bộ thư mục
tar -czf n8n-backup-$(date +%Y%m%d).tar.gz /home/n8n

# Backup chỉ dữ liệu
cp -r /home/n8n /home/n8n-backup-$(date +%Y%m%d)

# Backup database (nếu sử dụng)
docker-compose exec n8n n8n export:workflow --backup --output=/home/node/.n8n/backup-$(date +%Y%m%d).json
```

### Restore N8N
```bash
# Restore từ backup
tar -xzf n8n-backup-YYYYMMDD.tar.gz -C /

# Hoặc copy trực tiếp
cp -r /home/n8n-backup-YYYYMMDD/* /home/n8n/

# Restart sau khi restore
cd /home/n8n && docker-compose restart
```

## 6. TROUBLESHOOTING

### Xem logs để debug
```bash
# Xem logs chi tiết
docker-compose logs -f n8n
docker-compose logs -f caddy

# Xem logs từ thời điểm cụ thể
docker-compose logs --since="2024-01-01" n8n

# Lưu logs ra file
docker-compose logs n8n > n8n-logs.txt
```

### Khắc phục sự cố
```bash
# Restart containers
docker-compose restart

# Rebuild containers (nếu cần)
docker-compose down
docker-compose up -d --force-recreate

# Xóa containers và tạo lại
docker-compose down -v
docker-compose up -d

# Kiểm tra disk space
df -h
du -sh /home/n8n

# Kiểm tra quyền thư mục
ls -la /home/n8n
chown -R 1000:1000 /home/n8n
chmod -R 755 /home/n8n
```

### Dọn dẹp Docker
```bash
# Xóa images không sử dụng
docker image prune -a

# Xóa containers dừng
docker container prune

# Xóa volumes không sử dụng
docker volume prune

# Dọn dẹp toàn bộ
docker system prune -a
```

## 7. MONITORING VÀ MAINTENANCE

### Kiểm tra tài nguyên
```bash
# Kiểm tra CPU, RAM usage
docker stats

# Kiểm tra disk space
df -h /home/n8n

# Kiểm tra network
docker network ls
docker-compose exec n8n ping google.com
```

### Maintenance định kỳ
```bash
# Script maintenance hàng tuần
#!/bin/bash
echo "🔧 Bắt đầu maintenance N8N..."

# Backup
echo "📦 Tạo backup..."
cp -r /home/n8n /home/n8n-backup-$(date +%Y%m%d)

# Cập nhật
echo "🚀 Kiểm tra cập nhật..."
cd /home/n8n
docker-compose pull
docker-compose up -d

# Dọn dẹp
echo "🧹 Dọn dẹp..."
docker image prune -f

echo "✅ Maintenance hoàn tất!"
```

## 8. LỆNH NHANH THƯỜNG DÙNG

```bash
# Khởi động N8N
cd /home/n8n && docker-compose up -d

# Dừng N8N
cd /home/n8n && docker-compose down

# Restart N8N
cd /home/n8n && docker-compose restart

# Xem logs
cd /home/n8n && docker-compose logs -f n8n

# Cập nhật N8N
cd /home/n8n && docker-compose pull && docker-compose up -d

# Kiểm tra phiên bản
docker exec -it n8n_n8n_1 n8n --version

# Backup nhanh
cp -r /home/n8n /home/n8n-backup-$(date +%Y%m%d)

# Kiểm tra trạng thái
cd /home/n8n && docker-compose ps
```

## 9. ALIAS HỮU ÍCH

Thêm vào ~/.bashrc:
```bash
alias n8n-start="cd /home/n8n && docker-compose up -d"
alias n8n-stop="cd /home/n8n && docker-compose down"  
alias n8n-restart="cd /home/n8n && docker-compose restart"
alias n8n-logs="cd /home/n8n && docker-compose logs -f n8n"
alias n8n-status="cd /home/n8n && docker-compose ps"
alias n8n-update="cd /home/n8n && docker-compose pull && docker-compose up -d"
alias n8n-backup="cp -r /home/n8n /home/n8n-backup-$(date +%Y%m%d)"
alias n8n-version="docker exec -it n8n_n8n_1 n8n --version"
```

Sau đó chạy: `source ~/.bashrc`

## 10. THÔNG TIN LIÊN HỆ VÀ HỖ TRỢ

- 🌐 Truy cập N8N: https://yourdomain.com
- 📚 Tài liệu chính thức: https://docs.n8n.io
- 🆘 Community: https://community.n8n.io
- 🐛 Báo lỗi: https://github.com/n8n-io/n8n/issues

---
**Lưu ý**: Thay thế `yourdomain.com` bằng domain thực tế của bạn trong các lệnh trên.
