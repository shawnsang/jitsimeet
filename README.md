# Jitsi Meet 会议系统部署文档

## 项目概述

本项目提供了一个完整的 Jitsi Meet 会议系统部署方案，专为个人或小团队使用而设计，具有以下特点：

- **低成本部署**：基于 Docker 容器化部署，资源占用少
- **灵活认证**：支持固定例会免认证和临时会议密码认证
- **自动监控**：集成 Uptime Kuma 监控和自动重启功能
- **安全可靠**：Nginx 反向代理 + SSL 证书保障安全

## 项目结构

### 📁 核心文件结构

```
jistimeet/
├── .env.development          # 开发环境配置模板
├── .env.example              # 环境配置示例文件
├── .gitignore                # Git 忽略文件配置
├── README.md                 # 项目说明文档
├── auth-config.lua           # Jitsi 认证配置
├── deploy.sh                 # 部署脚本
├── docker-compose.yml        # Docker 容器编排配置
├── generate-ssl.sh           # SSL 证书生成和管理脚本
├── health-check.sh           # 系统健康检查脚本
├── maintenance.sh            # 自动化维护脚本
└── nginx.conf                # Nginx 反向代理配置
```

### 📋 文件说明

**🔧 配置文件**
- **`.env.development`** - 开发环境配置模板，包含调试设置
- **`.env.example`** - 通用环境配置示例，支持多种部署场景
- **`docker-compose.yml`** - Docker 服务编排，定义所有必需的容器
- **`nginx.conf`** - Nginx 配置，包含 SSL、安全头和性能优化
- **`auth-config.lua`** - Jitsi 认证逻辑，支持公开和私有房间

**🚀 部署和管理脚本**
- **`deploy.sh`** - 主部署脚本，包含环境验证和服务启动
- **`generate-ssl.sh`** - SSL 证书管理，支持自签名和 Let's Encrypt
- **`health-check.sh`** - 系统监控，检查服务状态和资源使用
- **`maintenance.sh`** - 自动化维护，包含备份、清理和优化

### 🗂️ 运行时目录（自动创建）

以下目录在运行时自动创建，已在 `.gitignore` 中排除：

```
jistimeet/
├── ssl/                      # SSL 证书存储
├── logs/                     # 日志文件
├── backups/                  # 配置备份
├── config/                   # 运行时配置
└── monitoring-data/          # 监控数据
```

## 系统架构

本部署方案采用容器化架构，专为小团队（50人以下）优化，包含以下核心服务：

### 核心服务
- **Nginx**: 反向代理服务，处理HTTPS终端和SSL证书管理
- **Web**: Jitsi Meet 前端界面
- **Prosody**: XMPP 服务器，处理信令
- **Jicofo**: 会议焦点组件，管理会议
- **JVB**: 视频桥接器，处理媒体流

### 监控服务
- **Uptime Kuma**: 系统监控和健康检查

### 架构优势
- **简化配置**: 专为小团队优化，配置简单易维护
- **HTTPS支持**: Nginx提供SSL终端，确保通信安全
- **容器化部署**: Docker Compose一键部署，易于管理
- **实时监控**: 内置监控服务，及时发现问题
- **资源优化**: 针对小规模使用场景优化资源配置

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

### 3. 选择环境配置模板

根据你的部署环境选择合适的配置模板：

```bash
# 开发环境
cp .env.development .env

# 生产环境
cp .env.example .env

# 编辑配置文件，重点配置以下项目：
# - PUBLIC_URL: 您的域名
# - DOCKER_HOST_ADDRESS: 服务器IP地址
# - LETSENCRYPT_EMAIL: Let's Encrypt证书申请邮箱
vim .env
```

**必须修改的配置项：**
- `PUBLIC_URL`: 您的域名（如：https://meet.yourdomain.com）
- `DOCKER_HOST_ADDRESS`: 服务器公网IP地址

### 🎯 简化配置说明

**一次配置，处处使用**：只需在 `.env` 文件中配置域名、IP和邮箱，后续所有操作都会自动读取这些配置，无需重复输入！

- `./deploy.sh init` - 自动读取域名和IP配置
- `./generate-ssl.sh` - 自动读取域名和邮箱配置
- `./deploy.sh ssl` - 自动读取域名和邮箱配置

这样可以避免在多个步骤中重复输入相同信息，提高部署效率。

### 4. 配置部署

```bash
# 给脚本添加执行权限
chmod +x deploy.sh generate-ssl.sh health-check.sh maintenance.sh

# 初始化部署环境
./deploy.sh init
```

### 5. 配置 SSL 证书

使用提供的脚本生成SSL证书：

```bash
# 生成自签名证书（测试用）- 自动读取.env配置
./generate-ssl.sh -t self-signed

# 申请Let's Encrypt证书（生产环境推荐）- 自动读取.env配置
./generate-ssl.sh -t letsencrypt

# 检查证书有效性
./generate-ssl.sh -c

# 自动续期Let's Encrypt证书
./generate-ssl.sh -t letsencrypt -a
```

#### 手动指定参数（可选）

如果需要覆盖.env文件中的配置：

```bash
# 手动指定域名和邮箱
./generate-ssl.sh -d custom-domain.com -e custom@email.com -t letsencrypt

# 使用传统certbot方式
sudo certbot --nginx -d meet.yourdomain.com
```

### 6. 启动服务

```bash
# 启动所有服务
./deploy.sh start

# 检查服务状态
./deploy.sh status
```

### 7. 监控和维护

```bash
# 检查服务健康状态
./health-check.sh

# 执行系统维护
./maintenance.sh

# 查看服务日志
./deploy.sh logs
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

### 服务管理功能

```bash
# 查看服务日志
./deploy.sh logs

# 手动执行健康检查
./health-check.sh

# 手动重启服务
./deploy.sh restart
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

## 系统监控和维护

### 健康检查
使用内置的健康检查脚本监控系统状态：

```bash
# 完整健康检查
./health-check.sh

# 快速检查（仅检查容器状态）
./health-check.sh -q

# 生成详细报告
./health-check.sh -r

# 设置检查超时时间
./health-check.sh -t 60
```

### 系统维护
使用维护脚本进行系统维护：

```bash
# 创建配置备份
./maintenance.sh backup

# 从备份恢复配置
./maintenance.sh restore

# 清理日志和旧备份
./maintenance.sh cleanup

# Docker系统清理
./maintenance.sh docker-cleanup

# SSL证书续期检查
./maintenance.sh ssl-check

# 系统更新检查
./maintenance.sh update-check

# 性能优化
./maintenance.sh optimize

# 查看维护状态
./maintenance.sh status

# 执行完整维护
./maintenance.sh full
```

### 自动化维护
设置定时任务进行自动维护：

```bash
# 编辑crontab
crontab -e

# 添加以下任务：
# 每天凌晨2点执行健康检查
0 2 * * * /path/to/jitsi-meet/health-check.sh -q >> /var/log/jitsi-health.log 2>&1

# 每周日凌晨3点执行完整维护
0 3 * * 0 /path/to/jitsi-meet/maintenance.sh full >> /var/log/jitsi-maintenance.log 2>&1

# 每月1号检查SSL证书
0 4 1 * * /path/to/jitsi-meet/maintenance.sh ssl-check >> /var/log/jitsi-ssl.log 2>&1
```

### 监控指标
系统会自动监控以下指标：

- **系统资源**：CPU、内存、磁盘使用率
- **容器状态**：所有Jitsi Meet服务的运行状态
- **SSL证书**：证书有效期和到期提醒
- **服务连通性**：HTTPS端点和监控服务可访问性
- **日志文件**：日志大小和清理状态
- **Docker资源**：镜像、容器、卷的使用情况

## 故障排除

### 常见问题

1. **无法访问会议室**
   ```bash
   # 检查服务状态
   ./deploy.sh status
   
   # 检查日志
   ./deploy.sh logs web
   
   # 运行健康检查
   ./health-check.sh
   ```

2. **SSL 证书问题**
   ```bash
   # 重新申请证书
   sudo certbot renew
   
   # 检查证书状态
   sudo certbot certificates
   
   # 使用维护脚本检查
   ./maintenance.sh ssl-check
   ```

3. **音视频连接问题**
   ```bash
   # 检查 JVB 端口
   netstat -tulnp | grep 10000
   
   # 检查防火墙设置
   sudo ufw status
   
   # 查看JVB日志
   docker logs jitsi_jvb
   ```

4. **性能问题**
   ```bash
   # 运行性能优化
   ./maintenance.sh optimize
   
   # 检查系统资源
   ./health-check.sh
   
   # 清理Docker系统
   ./maintenance.sh docker-cleanup
   ```

### Docker Compose 诊断命令

如果遇到问题，可以使用以下命令进行诊断：

```bash
# 查看所有服务状态
docker-compose ps

# 查看特定服务日志
docker-compose logs web
docker-compose logs prosody
docker-compose logs jicofo
docker-compose logs jvb
docker-compose logs nginx

# 重启特定服务
docker-compose restart web
docker-compose restart nginx

# 完全重建服务
docker-compose down
docker-compose up -d --build
```

#### Nginx 相关问题

**Nginx 启动失败**
- 检查 `.env` 文件中的 `SSL_CERT_PATH` 和 `SSL_KEY_PATH` 是否正确
- 确保 SSL 证书文件存在且可读
- 查看 nginx 日志：`docker-compose logs nginx`

**SSL 证书问题**
- 验证证书有效性：`./generate-ssl.sh -c`
- 重新生成证书：`./generate-ssl.sh`
- 检查域名 DNS 解析是否正确

**环境变量模板问题**
- 确保 `.env` 文件包含所有必需的变量
- 检查 nginx.conf.template 是否正确替换变量
- 验证生成的 nginx.conf 文件内容

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
2. 健康状态：`./health-check.sh`
3. 服务状态：`./deploy.sh status`
4. 网络连接：`netstat -tulnp`

## 许可证

本项目基于 Apache 2.0 许可证开源。

## 更新日志

- **v1.0**: 初始版本，支持基本的会议功能和监控
- 后续版本将添加更多功能和优化

---

**注意**: 请根据实际情况修改配置文件中的域名、IP地址等信息。