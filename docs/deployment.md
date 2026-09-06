# Whimread 部署指南

## 目录
- [生产环境部署](#生产环境部署)
- [开发环境部署](#开发环境部署)
- [Docker 部署](#docker-部署)
- [环境变量配置](#环境变量配置)
- [监控和维护](#监控和维护)

## 生产环境部署

### 系统要求

**硬件要求**
- CPU: 2核心以上
- 内存: 4GB 以上
- 存储: 20GB 以上可用空间
- 网络: 稳定的互联网连接

**软件要求**
- Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- Docker 20.10+
- Docker Compose 2.0+
- Nginx (推荐用于反向代理)

### 部署步骤

#### 1. 准备环境

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 重新登录以应用用户组变更
```

#### 2. 获取代码

```bash
# 克隆项目
git clone https://github.com/yunkst/novel_builder.git
cd novel_builder

# 检出稳定版本
git checkout v1.0.0  # 或最新的稳定版本
```

#### 3. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑环境变量
nano .env
```

必须配置的环境变量：
```env
# 数据库配置
DATABASE_URL=postgresql://novel_user:your_password@postgres:5432/novel_db

# API 访问令牌
NOVEL_API_TOKEN=your_secure_api_token_here

COMFYUI_API_URL=http://your-comfyui-server:8188
```

> 注：`NOVEL_ENABLED_SITES` 等爬虫站点列表已于 v2.0.x 移除（爬虫 2026-07-08 整体下线，章节由前端 Headless WebView 提取）。

#### 4. 配置反向代理（Nginx）

```nginx
# /etc/nginx/sites-available/novel-builder
server {
    listen 80;
    server_name your-domain.com;

    # 重定向到 HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL 证书配置
    ssl_certificate /path/to/your/cert.pem;
    ssl_certificate_key /path/to/your/private.key;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;

    # 后端 API 代理
    location /api/ {
        proxy_pass http://localhost:3800/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 静态文件服务（用于 Flutter Web）
    location / {
        root /path/to/novel_builder/web;
        try_files $uri $uri/ /index.html;
    }

    # 文件上传大小限制
    client_max_body_size 10M;
}
```

#### 5. 启动服务

```bash
# 构建并启动服务（本仓库仅 docker-compose.yml，backend + postgres）
docker-compose up -d --build

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

#### 6. 数据库初始化

```bash
# 运行数据库迁移
docker-compose exec backend alembic upgrade head

# 创建初始用户（如果需要）
docker-compose exec backend python -m app.scripts.create_admin
```

## 开发环境部署

### 快速启动

```bash
# 克隆项目
git clone https://github.com/yunkst/novel_builder.git
cd novel_builder

# 启动开发环境
docker-compose up -d

# 启动 Flutter 应用
cd novel_app
flutter pub get
flutter run
```

### 本地开发

#### 后端开发

```bash
cd backend

# 创建虚拟环境
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 安装依赖
pip install -r requirements.txt

# 启动数据库
docker-compose up -d postgres

# 运行迁移
alembic upgrade head

# 启动开发服务器
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

#### Flutter 开发

```bash
cd novel_app

# 安装依赖
flutter pub get

# 连接设备并运行
flutter devices
flutter run -d <device_id>
```

## Docker 部署

### 生产化说明

本仓库仅提供 `docker-compose.yml`（backend + postgres 容器）。**生产化所需组件由各运维团队按场景自行配置**，常见选项：

- **反向代理 + HTTPS**：Nginx / Caddy / Traefik（自行签发或 Let's Encrypt）
- **进程守护**：`systemd` / Docker restart policy / K8s
- **数据库高可用**：PostgreSQL 主从、备份策略
- **对象存储**：备份文件、模型权重落 OSS / MinIO

> 仓库不再提供 `docker-compose.prod.yml`、`docker-compose.monitoring.yml` 等编排模板（早期含 redis/nginx/prometheus/grafana 的版本于 2026-07-08 移除），如需请参照团队现有规范。

### 健康检查配置

在 `docker-compose.yml` 中添加健康检查：

```yaml
services:
  backend:
    # ... 其他配置
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  postgres:
    # ... 其他配置
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
```

## 环境变量配置

### 完整环境变量列表

```env
# 数据库配置
DATABASE_URL=postgresql://username:password@host:port/database
POSTGRES_DB=novel_db
POSTGRES_USER=novel_user
POSTGRES_PASSWORD=secure_password

# API 配置
NOVEL_API_TOKEN=your_api_token_here

# 服务配置
DEBUG=false
CORS_ORIGINS=["https://your-domain.com"]

COMFYUI_API_URL=http://your-comfyui-server:8188

# 代理配置（可选）
HTTP_PROXY=http://proxy.example.com:8080
HTTPS_PROXY=http://proxy.example.com:8080
```

> 注：早期文档中提及的 `REDIS_URL` / `CACHE_TTL` / `SECRET_KEY` / `ACCESS_TOKEN_EXPIRE_MINUTES` / `MAX_UPLOAD_SIZE` / `UPLOAD_DIR` / `LOG_LEVEL` / `HOST` / `PORT` 字段已对齐到 v2.0.x（爬虫/缓存表 2026-07-08 下线后简化），请以 `.env.example` 为准。

### 安全配置

1. **数据库安全**
```bash
# 创建专用数据库用户
CREATE USER novel_user WITH PASSWORD 'secure_password';
CREATE DATABASE novel_db OWNER novel_user;
GRANT ALL PRIVILEGES ON DATABASE novel_db TO novel_user;
```

2. **API 安全**
- 使用强密码作为 API Token
- 定期轮换密钥
- 限制 CORS 来源

3. **SSL/TLS 配置**
- 使用 Let's Encrypt 免费证书
- 定期更新证书
- 禁用弱加密算法

## 监控和维护

### 日志管理

```bash
# 查看应用日志
docker-compose logs -f backend

# 查看数据库日志
docker-compose logs -f postgres

# 日志轮转配置
# /etc/logrotate.d/novel-builder
/var/log/novel-builder/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        docker-compose restart backend
    endscript
}
```

### 备份策略

```bash
#!/bin/bash
# backup.sh - 数据库备份脚本

BACKUP_DIR="/backups/novel-builder"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份数据库
docker-compose exec -T postgres pg_dump -U novel_user novel_db > $BACKUP_DIR/db_backup_$DATE.sql

# 备份应用数据
docker run --rm -v novel_builder_postgres_data:/data -v $BACKUP_DIR:/backup ubuntu tar czf /backup/data_backup_$DATE.tar.gz -C /data .

# 清理旧备份（保留30天）
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
```

### 性能监控

本仓库不内置 Prometheus/Grafana 模板（2026-07-08 移除 `docker-compose.monitoring.yml`）。如需指标采集，建议：

- **后端指标**：FastAPI `prometheus-fastapi-instrumentator`（需自行加）
- **数据库指标**：`postgres_exporter`
- **可视化**：Grafana 接入团队现有 Prometheus 实例

也可用 hosted APM（如 OpenObserve / Grafana Cloud），不强制绑定具体方案。

### 更新部署

```bash
#!/bin/bash
# update.sh - 应用更新脚本

echo "Starting update process..."

# 拉取最新代码
git fetch origin
git checkout master
git pull origin master

# 备份当前数据
./backup.sh

# 构建并重启服务
docker-compose pull
docker-compose up -d --build

# 运行数据库迁移
docker-compose exec backend alembic upgrade head

echo "Update completed successfully!"
```

## 故障排除

### 常见问题

1. **服务无法启动**
```bash
# 检查端口占用
sudo netstat -tulpn | grep :8000

# 检查 Docker 服务状态
sudo systemctl status docker

# 重新构建镜像
docker-compose build --no-cache
```

2. **数据库连接失败**
```bash
# 检查数据库容器状态
docker-compose ps postgres

# 查看数据库日志
docker-compose logs postgres

# 测试数据库连接
docker-compose exec backend python -c "from app.database import engine; print(engine.execute('SELECT 1').scalar())"
```

3. **内存不足**
```bash
# 检查系统资源
free -h
df -h

# 清理 Docker 资源
docker system prune -a
```

### 性能优化

1. **数据库优化**
- 添加适当的索引
- 配置连接池
- 定期清理日志

2. **应用优化**
- 优化 WebView 提取脚本预加载策略
- 合理控制 ComfyUI 并发请求数
- 启用静态文件压缩（gzip / brotli）

3. **系统优化**
- 调整 Docker 资源限制
- 使用 CDN 加速
- 启用 Gzip 压缩

## 联系支持

如果在部署过程中遇到问题，请通过以下方式获取帮助：

- GitHub Issues：https://github.com/yunkst/novel_builder/issues/new/choose
- 文档：https://novel-builder.readthedocs.io