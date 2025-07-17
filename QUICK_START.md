# Jitsi Meet 快速部署指南

## 🚀 一键部署流程

### 1. 准备工作

```bash
# 克隆项目
git clone <repository-url>
cd jitsi-meet

# 复制环境配置模板
cp .env.example .env
```

### 2. 配置环境变量（一次配置）

编辑 `.env` 文件，只需配置这三个关键项目：

```bash
# 您的域名
PUBLIC_URL=meet.yourdomain.com

# 服务器公网IP
DOCKER_HOST_ADDRESS=1.2.3.4

# Let's Encrypt 邮箱
LETSENCRYPT_EMAIL=admin@yourdomain.com
```

### 3. 自动化部署

```bash
# 初始化配置（自动读取.env中的域名和IP）
./deploy.sh init

# 生成SSL证书（自动读取.env中的域名和邮箱）
./generate-ssl.sh -t letsencrypt

# 启动服务
./deploy.sh start
```

### 4. 验证部署

```bash
# 检查服务状态
./deploy.sh status

# 检查健康状态
./health-check.sh

# 访问您的Jitsi Meet
# https://meet.yourdomain.com
```

## 🎯 优势特性

### ✅ 一次配置，处处使用
- 在 `.env` 文件中配置一次域名、IP、邮箱
- 所有脚本自动读取配置，无需重复输入
- 避免配置不一致的问题

### ✅ 智能配置检测
- 脚本会检测 `.env` 中的现有配置
- 如果配置有效，会询问是否使用
- 支持命令行参数覆盖 `.env` 配置

### ✅ 简化的命令
```bash
# 传统方式（需要重复输入）
./generate-ssl.sh -d meet.yourdomain.com -e admin@yourdomain.com -t letsencrypt

# 新方式（自动读取配置）
./generate-ssl.sh -t letsencrypt
```

## 🔧 高级用法

### 覆盖 .env 配置
如果需要临时使用不同的配置：

```bash
# 使用不同的域名
./generate-ssl.sh -d test.yourdomain.com -t self-signed

# 使用不同的邮箱
./generate-ssl.sh -e test@yourdomain.com -t letsencrypt
```

### 检查配置
```bash
# 检查证书状态
./generate-ssl.sh -c

# 查看当前配置
cat .env | grep -E "PUBLIC_URL|DOCKER_HOST_ADDRESS|LETSENCRYPT_EMAIL"
```

## 📝 注意事项

1. **DNS配置**：确保域名已正确解析到服务器IP
2. **防火墙**：开放必要端口（80, 443, 10000/UDP, 4443/TCP）
3. **Let's Encrypt**：域名必须公网可访问才能申请证书
4. **测试环境**：可以使用自签名证书进行测试

## 🆘 故障排除

```bash
# 检查服务状态
./deploy.sh status

# 查看日志
./deploy.sh logs

# 健康检查
./health-check.sh

# 重启服务
./deploy.sh restart
```

---

**提示**：这个简化的配置流程大大减少了部署复杂度，让您专注于业务而不是重复的配置工作！