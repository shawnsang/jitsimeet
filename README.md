# Jitsi Meet 会议系统部署文档

## 项目概述

本项目提供了一个完整的 Jitsi Meet 会议系统部署方案，专为个人或小团队使用而设计，具有以下特点：

- **低成本部署**：基于 Docker 容器化部署，资源占用少
- **灵活认证**：支持固定例会免认证和临时会议密码认证
- **自动监控**：集成 Uptime Kuma 监控和自动重启功能
- **安全可靠**：Nginx 反向代理 + SSL 证书保障安全

## 系统架构

本项目采用 Docker Compose 编排，包含以下核心服务：

### 核心服务
- **Nginx**: 负载均衡器和反向代理
- **Web**: Jitsi Meet 前端界面
- **Prosody**: XMPP 服务器，处理信令
- **Jicofo**: 会议焦点组件，管理会议
- **JVB**: 视频桥接器，处理媒体流

### 数据存储服务
- **PostgreSQL**: 持久化数据存储（会议记录、用户数据、统计信息）
- **Redis**: 缓存和会话管理（用户会话、实时状态、分布式缓存）

### 监控服务
- **Uptime Kuma**: 系统监控和健康检查

### 架构优势
- **高可用性**: Nginx 负载均衡支持多实例部署
- **数据持久化**: PostgreSQL 确保数据不丢失
- **高性能**: Redis 缓存提升响应速度
- **可扩展性**: 支持水平扩展和集群部署
- **监控完善**: 全面的健康检查和资源限制

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   用户浏览器    │────│  Nginx 反向代理  │────│  Jitsi Meet Web │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        │
                       ┌─────────────────┐    ┌─────────────────┐
                       │  SSL 证书管理   │    │   Prosody XMPP  │
                       └─────────────────┘    └─────────────────┘
                                                        │
                                              ┌─────────────────┐
                                              │     Jicofo      │
                                              └─────────────────┘
                                                        │
                                              ┌─────────────────┐
                                              │       JVB       │
                                              └─────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  PostgreSQL     │    │     Redis       │    │  Uptime Kuma    │
│   数据库        │    │     缓存        │    │     监控        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 核心需求实现

### 会议类型支持

1. **固定例会（免认证）**
   - 预定义房间名称：`daily-standup`, `team-meeting`, `weekly-review` 等
   - 直接通过链接加入，无需密码
   - 适合日常例会使用

2. **临时会议（密码认证）**
   - 房间名称以 `private-` 开头
   - 需要输入密码才能加入
   - 提供额外的安全保障

### 部署特性

- **Docker 容器化**：所有服务运行在 Docker 容器中
- **Nginx 反向代理**：处理 SSL 终止和负载均衡
- **自动监控**：Uptime Kuma 实时监控 + 异常自动重启
- **安全配置**：SSL/TLS 加密，安全头设置

## 系统要求

### 硬件要求

- **CPU**: 2核心以上
- **内存**: 4GB 以上
- **存储**: 20GB 以上可用空间
- **网络**: 公网IP地址，上行带宽 10Mbps 以上

### 软件要求

- **操作系统**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Nginx**: 1.18+ (可选，用于反向代理)
- **域名**: 已解析到服务器IP的域名

## 快速部署

### 1. 环境准备

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

# 安装 Nginx
sudo apt install nginx certbot python3-certbot-nginx -y
```

### 2. 下载部署文件

```bash
# 克隆或下载项目文件到服务器
mkdir -p /opt/jitsi-meet
cd /opt/jitsi-meet

# 将所有配置文件上传到此目录
```

### 3. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件
vim .env
```

**必须修改的配置项：**
- `PUBLIC_URL`: 您的域名（如：https://meet.yourdomain.com）
- `DOCKER_HOST_ADDRESS`: 服务器公网IP地址

### 4. 配置部署

```bash
# 给脚本添加执行权限
chmod +x deploy.sh auto-restart.sh

# 初始化部署环境
./deploy.sh init
```

### 5. 配置 SSL 证书

```bash
# 安装 SSL 证书
./deploy.sh ssl

# 或者手动配置
sudo certbot --nginx -d meet.yourdomain.com
```

### 6. 启动服务

```bash
# 启动所有服务
./deploy.sh start

# 检查服务状态
./deploy.sh status
```

### 7. 启动监控

```bash
# 启动自动监控和重启服务
./auto-restart.sh start

# 检查监控状态
./auto-restart.sh status
```

## Git 使用和文件管理

### 版本控制最佳实践

本项目已配置 `.gitignore` 文件，自动排除敏感文件和临时文件：

**被忽略的文件类型：**
- 环境配置文件（`.env`、`.env.local` 等）
- 配置目录（`config/`）
- 日志文件（`logs/`、`*.log`）
- SSL证书和密钥文件（`*.pem`、`*.key` 等）
- 备份文件（`backup/`、`*.backup`）
- 系统临时文件

### 初始化 Git 仓库

```bash
# 初始化 Git 仓库
git init

# 添加远程仓库
git remote add origin https://github.com/yourusername/jitsi-meet-deploy.git

# 添加文件到版本控制
git add .
git commit -m "Initial commit: Jitsi Meet deployment configuration"

# 推送到远程仓库
git push -u origin main
```

### 环境配置管理

```bash
# 复制环境变量模板（首次部署）
cp .env.example .env

# 编辑您的环境配置
vim .env

# 注意：.env 文件不会被提交到 Git
# 团队成员需要根据 .env.example 创建自己的 .env 文件
```

### 安全注意事项

⚠️ **重要提醒：**
- `.env` 文件包含敏感信息，已被 `.gitignore` 排除
- 配置目录 `config/` 包含运行时生成的密钥，不应提交
- SSL 证书和私钥文件已被自动排除
- 如需分享配置，请使用 `.env.example` 模板

### 团队协作流程

```bash
# 克隆项目
git clone https://github.com/yourusername/jitsi-meet-deploy.git
cd jitsi-meet-deploy

# 创建环境配置
cp .env.example .env
# 根据实际环境修改 .env 文件

# 部署服务
./deploy.sh init
./deploy.sh start
```

## 数据库架构说明

### PostgreSQL 数据库

**主要用途**:
- 会议记录和历史数据存储
- 用户信息和权限管理
- 录制文件元数据管理
- 系统配置和审计日志
- 统计数据和报表分析

**适用场景**:
- 需要数据持久化的生产环境
- 企业级部署和合规要求
- 大规模用户和会议管理
- 详细的数据分析和报表

### Redis 缓存

**主要用途**:
- 用户会话和登录状态管理
- 实时数据缓存和快速访问
- 分布式系统状态同步
- 消息队列和事件通知
- 热点数据缓存优化

**适用场景**:
- 高并发用户访问（>50用户）
- 多实例负载均衡部署
- 需要快速响应的实时功能
- 分布式架构和微服务

### 使用建议

| 部署规模 | PostgreSQL | Redis | 说明 |
|---------|------------|-------|---------|
| 小型（<50用户） | 可选 | 可选 | 默认内存存储足够 |
| 中型（50-200用户） | 推荐 | 推荐 | 提升性能和稳定性 |
| 大型（>200用户） | 必需 | 必需 | 确保系统可靠性 |
| 企业级 | 必需 | 必需 | 完整的数据管理方案 |

详细的数据库架构说明请参考：[数据库架构文档](docs/database-architecture.md)

## 详细配置说明

### 环境变量配置 (.env)

关键配置项说明：

```bash
# 基本配置
PUBLIC_URL=https://meet.yourdomain.com  # 您的域名
DOCKER_HOST_ADDRESS=YOUR_SERVER_IP      # 服务器公网IP

# 认证配置
ENABLE_AUTH=1          # 启用认证
AUTH_TYPE=internal     # 使用内部认证
ENABLE_GUESTS=1        # 允许访客

# 安全密钥（自动生成）
JICOFO_COMPONENT_SECRET=xxx
JVB_AUTH_PASSWORD=xxx
JICOFO_AUTH_PASSWORD=xxx
```

### Nginx 配置

主要特性：
- HTTP 到 HTTPS 自动重定向
- WebSocket 支持
- 静态文件缓存
- 安全头设置
- 速率限制

### 认证配置

通过 `auth-config.lua` 实现：

```lua
-- 公开房间（免认证）
public_rooms = {
    "daily-standup",
    "team-meeting",
    "weekly-review",
    -- 添加更多固定会议室
}

-- 私有房间前缀（需要密码）
private_room_prefix = "private-"
```

## 使用指南

### 创建固定例会

1. 访问：`https://meet.yourdomain.com/daily-standup`
2. 直接进入会议，无需密码
3. 适合日常例会使用

### 创建临时会议

1. 访问：`https://meet.yourdomain.com/private-meeting-name`
2. 输入密码：`meeting123`（默认密码）
3. 进入会议

### 自定义房间密码

编辑 `auth-config.lua` 文件：

```lua
-- 为特定房间设置密码
if room_name == "private-important" then
    expected_password = "important123"
elseif room_name == "private-executive" then
    expected_password = "exec456"
end
```

## 监控和维护

### Uptime Kuma 监控

访问监控面板：`https://monitor.yourdomain.com`

监控项目：
- Jitsi Meet Web 服务
- API 接口状态
- WebSocket 连接
- Docker 容器状态
- 系统资源使用

### 自动重启功能

```bash
# 查看监控日志
./auto-restart.sh logs

# 手动执行健康检查
./auto-restart.sh check

# 手动重启服务
./auto-restart.sh restart
```

### 日常维护命令

```bash
# 查看服务状态
./deploy.sh status

# 查看服务日志
./deploy.sh logs
./deploy.sh logs web  # 查看特定服务日志

# 更新服务
./deploy.sh update

# 备份配置
./deploy.sh backup
```

## 故障排除

### 常见问题

1. **无法访问会议室**
   ```bash
   # 检查服务状态
   ./deploy.sh status
   
   # 检查日志
   ./deploy.sh logs web
   ```

2. **SSL 证书问题**
   ```bash
   # 重新申请证书
   sudo certbot renew
   
   # 检查证书状态
   sudo certbot certificates
   ```

3. **音视频连接问题**
   ```bash
   # 检查 JVB 端口
   netstat -tulnp | grep 10000
   
   # 检查防火墙设置
   sudo ufw status
   ```

### 端口配置

确保以下端口开放：

- **80/443**: HTTP/HTTPS (Nginx)
- **8000**: Jitsi Meet Web
- **3001**: Uptime Kuma
- **10000/UDP**: JVB 媒体流
- **4443/TCP**: JVB TCP 回退

### 防火墙配置

```bash
# Ubuntu/Debian
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 10000/udp
sudo ufw allow 4443/tcp
sudo ufw enable

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=10000/udp
sudo firewall-cmd --permanent --add-port=4443/tcp
sudo firewall-cmd --reload
```

## 性能优化

### 系统优化

```bash
# 增加文件描述符限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# 优化网络参数
echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
sudo sysctl -p
```

### Docker 优化

```bash
# 限制日志大小
echo '{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}' | sudo tee /etc/docker/daemon.json

sudo systemctl restart docker
```

## 安全建议

1. **定期更新**
   ```bash
   # 定期更新系统和 Docker 镜像
   ./deploy.sh update
   ```

2. **密码安全**
   - 定期更换默认密码
   - 为重要会议设置强密码
   - 考虑使用环境变量管理密码

3. **网络安全**
   - 配置防火墙规则
   - 使用 fail2ban 防止暴力攻击
   - 定期检查访问日志

4. **备份策略**
   ```bash
   # 定期备份配置
   ./deploy.sh backup
   
   # 设置定时备份
   echo "0 2 * * * cd /opt/jitsi-meet && ./deploy.sh backup" | crontab -
   ```

## 扩展功能

### 录制功能

如需启用录制功能，修改 `.env` 文件：

```bash
ENABLE_RECORDING=1
```

然后添加 Jibri 服务到 `docker-compose.yml`。

### 电话接入

可以集成 Jigasi 组件实现电话接入功能。

### 自定义界面

通过修改 Web 容器的配置文件自定义界面样式和功能。

## 技术支持

如遇到问题，请检查：

1. 系统日志：`./deploy.sh logs`
2. 监控状态：`./auto-restart.sh status`
3. 服务状态：`./deploy.sh status`
4. 网络连接：`netstat -tulnp`

## 许可证

本项目基于 Apache 2.0 许可证开源。

## 更新日志

- **v1.0**: 初始版本，支持基本的会议功能和监控
- 后续版本将添加更多功能和优化

---

**注意**: 请根据实际情况修改配置文件中的域名、IP地址等信息。