#!/bin/bash

# Jitsi Meet 部署脚本
# 作者: AI Assistant
# 版本: 1.0
# 描述: 用于部署和管理 Jitsi Meet 会议系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    # 检查 OpenSSL
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL 未安装，请先安装 OpenSSL"
        exit 1
    fi
    
    # 检查 Nginx
    if ! command -v nginx &> /dev/null; then
        log_warning "Nginx 未安装，建议安装 Nginx 作为反向代理"
    fi
    
    log_success "依赖检查完成"
}

# 检查环境配置文件
check_env_file() {
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            log_error ".env 文件不存在"
            log_info "请执行以下命令创建环境配置文件："
            echo "  cp .env.example .env"
            echo "  vim .env  # 编辑配置文件"
            log_info "然后修改 PUBLIC_URL 和 DOCKER_HOST_ADDRESS 等配置项"
        else
            log_error ".env 和 .env.example 文件都不存在"
        fi
        exit 1
    fi
    
    # 检查是否还有未配置的占位符
    if grep -q "your-domain.com\|192.168.1.100\|CHANGE_ME" ".env"; then
        log_warning "检测到 .env 文件中还有未配置的占位符"
        log_info "请检查并修改以下配置项："
        grep -n "your-domain.com\|192.168.1.100\|CHANGE_ME" ".env" || true
        echo
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 生成随机密码
generate_password() {
    openssl rand -hex 16
}

# 初始化配置
init_config() {
    log_info "初始化配置..."
    
    # 创建配置目录
    mkdir -p "./config/{web,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}"
    mkdir -p ./logs
    
    # 生成密码
    if [ ! -f ".env" ] || grep -q "CHANGE_ME" ".env"; then
        log_info "生成安全密钥..."
        
        JICOFO_COMPONENT_SECRET=$(generate_password)
        JICOFO_AUTH_PASSWORD=$(generate_password)
        JVB_AUTH_PASSWORD=$(generate_password)
        JIBRI_RECORDER_PASSWORD=$(generate_password)
        JIBRI_XMPP_PASSWORD=$(generate_password)
        
        # 更新.env文件
        sed -i "s/JICOFO_COMPONENT_SECRET=.*/JICOFO_COMPONENT_SECRET=${JICOFO_COMPONENT_SECRET}/" ".env"
        sed -i "s/JICOFO_AUTH_PASSWORD=.*/JICOFO_AUTH_PASSWORD=${JICOFO_AUTH_PASSWORD}/" ".env"
        sed -i "s/JVB_AUTH_PASSWORD=.*/JVB_AUTH_PASSWORD=${JVB_AUTH_PASSWORD}/" ".env"
        sed -i "s/JIBRI_RECORDER_PASSWORD=.*/JIBRI_RECORDER_PASSWORD=${JIBRI_RECORDER_PASSWORD}/" ".env"
        sed -i "s/JIBRI_XMPP_PASSWORD=.*/JIBRI_XMPP_PASSWORD=${JIBRI_XMPP_PASSWORD}/" ".env"
        
        log_success "安全密钥已生成"
    fi
    
    # 设置权限
    chmod -R 755 ./config
    chmod 600 .env
    
    log_success "配置初始化完成"
}

# 配置域名和IP
configure_domain() {
    log_info "配置域名和IP地址..."
    
    read -p "请输入您的域名 (例如: meet.yourdomain.com): " DOMAIN
    read -p "请输入服务器公网IP地址: " SERVER_IP
    
    if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
        log_error "域名和IP地址不能为空"
        exit 1
    fi
    
    # 更新 .env 文件
    sed -i "s|PUBLIC_URL=.*|PUBLIC_URL=https://$DOMAIN|g" .env
    sed -i "s/DOCKER_HOST_ADDRESS=.*/DOCKER_HOST_ADDRESS=$SERVER_IP/g" .env
    
    # 更新 nginx 配置
    sed -i "s/meet.yourdomain.com/$DOMAIN/g" nginx.conf
    
    log_success "域名和IP配置完成"
}

# 启动服务
start_services() {
    log_info "启动 Jitsi Meet 服务..."
    
    # 使用 docker-compose 或 docker compose
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    log_success "服务启动完成"
    
    # 等待服务启动
    log_info "等待服务完全启动..."
    sleep 30
    
    # 检查服务状态
    check_services
}

# 停止服务
stop_services() {
    log_info "停止 Jitsi Meet 服务..."
    
    if command -v docker-compose &> /dev/null; then
        docker-compose down
    else
        docker compose down
    fi
    
    log_success "服务停止完成"
}

# 重启服务
restart_services() {
    log_info "重启 Jitsi Meet 服务..."
    stop_services
    sleep 5
    start_services
}

# 检查服务状态
check_services() {
    log_info "检查服务状态..."
    
    if command -v docker-compose &> /dev/null; then
        docker-compose ps
    else
        docker compose ps
    fi
    
    # 检查端口
    log_info "检查端口状态..."
    netstat -tlnp | grep -E ':(80|443|8000|3001|10000)\s' || true
}

# 查看日志
view_logs() {
    log_info "查看服务日志..."
    
    if [ -n "$1" ]; then
        if command -v docker-compose &> /dev/null; then
            docker-compose logs -f "$1"
        else
            docker compose logs -f "$1"
        fi
    else
        if command -v docker-compose &> /dev/null; then
            docker-compose logs -f
        else
            docker compose logs -f
        fi
    fi
}

# 更新服务
update_services() {
    log_info "更新 Jitsi Meet 服务..."
    
    # 拉取最新镜像
    if command -v docker-compose &> /dev/null; then
        docker-compose pull
        docker-compose up -d
    else
        docker compose pull
        docker compose up -d
    fi
    
    # 清理旧镜像
    docker image prune -f
    
    log_success "服务更新完成"
}

# 备份配置
backup_config() {
    log_info "备份配置文件..."
    
    BACKUP_DIR="backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    cp -r config/ "$BACKUP_DIR/"
    cp .env "$BACKUP_DIR/"
    cp docker-compose.yml "$BACKUP_DIR/"
    
    log_success "配置备份完成: $BACKUP_DIR"
}

# 安装 SSL 证书
install_ssl() {
    log_info "安装 SSL 证书..."
    
    read -p "请输入您的邮箱地址 (用于 Let's Encrypt): " EMAIL
    read -p "请输入您的域名: " DOMAIN
    
    if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ]; then
        log_error "邮箱和域名不能为空"
        exit 1
    fi
    
    # 创建 SSL 目录
    sudo mkdir -p /etc/nginx/ssl
    
    # 使用 Certbot 获取证书
    if command -v certbot &> /dev/null; then
        sudo certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
        
        # 复制证书到 nginx 目录
        sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/nginx/ssl/
        sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/nginx/ssl/
        
        log_success "SSL 证书安装完成"
    else
        log_error "Certbot 未安装，请先安装 Certbot"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    echo "Jitsi Meet 部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  init        初始化部署环境"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看服务状态"
    echo "  logs [服务] 查看日志"
    echo "  update      更新服务"
    echo "  backup      备份配置"
    echo "  ssl         安装SSL证书"
    echo "  help        显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 init     # 初始化部署"
    echo "  $0 start    # 启动所有服务"
    echo "  $0 logs web # 查看web服务日志"
}

# 主函数
main() {
    case "$1" in
        init)
            check_dependencies
            check_env_file
            init_config
            configure_domain
            log_success "初始化完成！请运行 '$0 start' 启动服务"
            ;;
        start)
            check_env_file
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            check_services
            ;;
        logs)
            view_logs "$2"
            ;;
        update)
            update_services
            ;;
        backup)
            backup_config
            ;;
        ssl)
            install_ssl
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"