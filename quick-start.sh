#!/bin/bash

# Jitsi Meet 快速启动脚本
# 一键部署 Jitsi Meet 会议系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Jitsi Meet 快速部署                      ║"
    echo "║                                                              ║"
    echo "║  🎥 个人会议系统 | 🔒 安全可靠 | 📊 自动监控 | 💰 低成本      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -eq 0 ]; then
        log_warning "检测到 root 用户，建议使用普通用户运行此脚本"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 检查操作系统
check_os() {
    log_step "检查操作系统..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            OS="debian"
            log_info "检测到 Debian/Ubuntu 系统"
        elif [ -f /etc/redhat-release ]; then
            OS="redhat"
            log_info "检测到 RedHat/CentOS 系统"
        else
            OS="unknown"
            log_warning "未知的 Linux 发行版"
        fi
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
}

# 安装系统依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    if [ "$OS" = "debian" ]; then
        sudo apt update
        sudo apt install -y curl wget git openssl net-tools
    elif [ "$OS" = "redhat" ]; then
        sudo yum update -y
        sudo yum install -y curl wget git openssl net-tools
    fi
    
    log_success "系统依赖安装完成"
}

# 安装 Docker
install_docker() {
    log_step "安装 Docker..."
    
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装，版本: $(docker --version)"
    else
        log_info "正在安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        log_success "Docker 安装完成"
    fi
    
    # 安装 Docker Compose
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        log_info "Docker Compose 已安装"
    else
        log_info "正在安装 Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose 安装完成"
    fi
}

# 安装 Nginx
install_nginx() {
    log_step "安装 Nginx..."
    
    if command -v nginx &> /dev/null; then
        log_info "Nginx 已安装"
    else
        if [ "$OS" = "debian" ]; then
            sudo apt install -y nginx certbot python3-certbot-nginx
        elif [ "$OS" = "redhat" ]; then
            sudo yum install -y nginx certbot python3-certbot-nginx
        fi
        log_success "Nginx 安装完成"
    fi
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow 10000/udp
        sudo ufw allow 4443/tcp
        sudo ufw --force enable
        log_success "UFW 防火墙配置完成"
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL
        sudo firewall-cmd --permanent --add-port=22/tcp
        sudo firewall-cmd --permanent --add-port=80/tcp
        sudo firewall-cmd --permanent --add-port=443/tcp
        sudo firewall-cmd --permanent --add-port=10000/udp
        sudo firewall-cmd --permanent --add-port=4443/tcp
        sudo firewall-cmd --reload
        log_success "Firewalld 防火墙配置完成"
    else
        log_warning "未检测到防火墙，请手动配置端口开放"
    fi
}

# 获取用户输入
get_user_input() {
    log_step "收集配置信息..."
    
    echo
    echo -e "${CYAN}请提供以下信息来配置您的 Jitsi Meet 系统：${NC}"
    echo
    
    # 域名
    while true; do
        read -p "请输入您的域名 (例如: meet.example.com): " DOMAIN
        if [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            log_error "请输入有效的域名格式"
        fi
    done
    
    # 服务器IP
    while true; do
        # 尝试自动获取公网IP
        AUTO_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "")
        if [ -n "$AUTO_IP" ]; then
            read -p "检测到服务器IP: $AUTO_IP，是否使用？(Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                read -p "请输入服务器公网IP: " SERVER_IP
            else
                SERVER_IP=$AUTO_IP
            fi
        else
            read -p "请输入服务器公网IP: " SERVER_IP
        fi
        
        if [[ $SERVER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            log_error "请输入有效的IP地址格式"
        fi
    done
    
    # 邮箱（用于SSL证书）
    while true; do
        read -p "请输入邮箱地址 (用于SSL证书申请): " EMAIL
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            log_error "请输入有效的邮箱地址"
        fi
    done
    
    # 默认密码
    read -p "请设置临时会议默认密码 (留空使用 'meeting123'): " DEFAULT_PASSWORD
    if [ -z "$DEFAULT_PASSWORD" ]; then
        DEFAULT_PASSWORD="meeting123"
    fi
    
    # 确认信息
    echo
    echo -e "${CYAN}配置信息确认：${NC}"
    echo -e "域名: ${GREEN}$DOMAIN${NC}"
    echo -e "服务器IP: ${GREEN}$SERVER_IP${NC}"
    echo -e "邮箱: ${GREEN}$EMAIL${NC}"
    echo -e "默认密码: ${GREEN}$DEFAULT_PASSWORD${NC}"
    echo
    
    read -p "确认以上信息正确？(Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "重新配置..."
        get_user_input
    fi
}

# 更新配置文件
update_config() {
    log_step "更新配置文件..."
    
    # 更新 .env 文件
    sed -i "s|PUBLIC_URL=.*|PUBLIC_URL=https://$DOMAIN|g" .env
    sed -i "s/DOCKER_HOST_ADDRESS=.*/DOCKER_HOST_ADDRESS=$SERVER_IP/g" .env
    sed -i "s/default_password = .*/default_password = \"$DEFAULT_PASSWORD\"/g" auth-config.lua
    
    # 更新 Nginx 配置
    sed -i "s/meet.yourdomain.com/$DOMAIN/g" nginx.conf
    sed -i "s/monitor.yourdomain.com/monitor.$DOMAIN/g" nginx.conf
    
    log_success "配置文件更新完成"
}

# 生成安全密钥
generate_secrets() {
    log_step "生成安全密钥..."
    
    if grep -q "CHANGE_ME" .env; then
        JICOFO_COMPONENT_SECRET=$(openssl rand -hex 16)
        JICOFO_AUTH_PASSWORD=$(openssl rand -hex 16)
        JVB_AUTH_PASSWORD=$(openssl rand -hex 16)
        JIBRI_RECORDER_PASSWORD=$(openssl rand -hex 16)
        JIBRI_XMPP_PASSWORD=$(openssl rand -hex 16)
        
        sed -i "s/JICOFO_COMPONENT_SECRET=.*/JICOFO_COMPONENT_SECRET=$JICOFO_COMPONENT_SECRET/" .env
        sed -i "s/JICOFO_AUTH_PASSWORD=.*/JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD/" .env
        sed -i "s/JVB_AUTH_PASSWORD=.*/JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD/" .env
        sed -i "s/JIBRI_RECORDER_PASSWORD=.*/JIBRI_RECORDER_PASSWORD=$JIBRI_RECORDER_PASSWORD/" .env
        sed -i "s/JIBRI_XMPP_PASSWORD=.*/JIBRI_XMPP_PASSWORD=$JIBRI_XMPP_PASSWORD/" .env
        
        log_success "安全密钥生成完成"
    else
        log_info "安全密钥已存在，跳过生成"
    fi
}

# 初始化目录结构
init_directories() {
    log_step "初始化目录结构..."
    
    mkdir -p config/{web,prosody,jicofo,jvb}
    mkdir -p config/prosody/{config,prosody-plugins-custom}
    mkdir -p config/web/{crontabs,transcripts}
    mkdir -p logs backup
    
    chmod -R 755 config/
    chmod +x deploy.sh auto-restart.sh
    
    log_success "目录结构初始化完成"
}

# 配置 Nginx
configure_nginx() {
    log_step "配置 Nginx..."
    
    # 备份原配置
    if [ -f /etc/nginx/sites-available/default ]; then
        sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup
    fi
    
    # 创建 Jitsi Meet 配置
    sudo cp nginx.conf /etc/nginx/sites-available/jitsi-meet
    
    # 启用站点
    sudo ln -sf /etc/nginx/sites-available/jitsi-meet /etc/nginx/sites-enabled/
    
    # 测试配置
    if sudo nginx -t; then
        log_success "Nginx 配置验证通过"
    else
        log_error "Nginx 配置验证失败"
        exit 1
    fi
}

# 申请 SSL 证书
setup_ssl() {
    log_step "申请 SSL 证书..."
    
    # 创建 webroot 目录
    sudo mkdir -p /var/www/certbot
    
    # 临时启动 Nginx
    sudo systemctl start nginx
    
    # 申请证书
    sudo certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" -d "monitor.$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
    
    if [ $? -eq 0 ]; then
        # 创建 SSL 目录并复制证书
        sudo mkdir -p /etc/nginx/ssl
        sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/nginx/ssl/
        sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/nginx/ssl/
        
        # 设置自动续期
        echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
        
        log_success "SSL 证书申请成功"
    else
        log_error "SSL 证书申请失败，请检查域名解析"
        exit 1
    fi
}

# 启动服务
start_services() {
    log_step "启动 Jitsi Meet 服务..."
    
    # 启动 Docker 服务
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    # 重启 Nginx
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    log_success "服务启动完成"
    
    # 等待服务启动
    log_info "等待服务完全启动..."
    sleep 30
}

# 启动监控
start_monitoring() {
    log_step "启动监控服务..."
    
    ./auto-restart.sh start
    
    log_success "监控服务启动完成"
}

# 验证部署
verify_deployment() {
    log_step "验证部署状态..."
    
    # 检查服务状态
    if command -v docker-compose &> /dev/null; then
        docker-compose ps
    else
        docker compose ps
    fi
    
    # 检查端口
    echo
    log_info "检查端口状态:"
    netstat -tlnp | grep -E ':(80|443|8000|3001|10000)\s' || true
    
    # 测试 HTTP 连接
    echo
    log_info "测试服务连接:"
    
    if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200\|301\|302"; then
        log_success "Jitsi Meet 服务正常"
    else
        log_warning "Jitsi Meet 服务可能未完全启动"
    fi
    
    if curl -s -o /dev/null -w "%{http_code}" "https://monitor.$DOMAIN" | grep -q "200\|301\|302"; then
        log_success "监控服务正常"
    else
        log_warning "监控服务可能未完全启动"
    fi
}

# 显示完成信息
show_completion() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 部署完成！                            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}访问地址：${NC}"
    echo -e "  📹 Jitsi Meet: ${GREEN}https://$DOMAIN${NC}"
    echo -e "  📊 监控面板:   ${GREEN}https://monitor.$DOMAIN${NC}"
    echo
    echo -e "${CYAN}会议室使用：${NC}"
    echo -e "  🔓 固定例会 (免认证):"
    echo -e "     https://$DOMAIN/daily-standup"
    echo -e "     https://$DOMAIN/team-meeting"
    echo -e "     https://$DOMAIN/weekly-review"
    echo
    echo -e "  🔒 临时会议 (需要密码):"
    echo -e "     https://$DOMAIN/private-meeting-name"
    echo -e "     密码: ${GREEN}$DEFAULT_PASSWORD${NC}"
    echo
    echo -e "${CYAN}管理命令：${NC}"
    echo -e "  查看状态: ${YELLOW}./deploy.sh status${NC}"
    echo -e "  查看日志: ${YELLOW}./deploy.sh logs${NC}"
    echo -e "  重启服务: ${YELLOW}./deploy.sh restart${NC}"
    echo -e "  监控状态: ${YELLOW}./auto-restart.sh status${NC}"
    echo
    echo -e "${YELLOW}注意事项：${NC}"
    echo -e "  1. 请确保域名已正确解析到服务器IP"
    echo -e "  2. 首次访问可能需要等待几分钟服务完全启动"
    echo -e "  3. 建议定期备份配置: ./deploy.sh backup"
    echo -e "  4. SSL 证书会自动续期"
    echo
}

# 检查和创建环境配置文件
setup_env_file() {
    log_step "配置环境文件..."
    
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            log_success "已从 .env.example 创建 .env 文件"
        else
            log_error ".env.example 文件不存在"
            exit 1
        fi
    else
        log_info ".env 文件已存在"
    fi
}

# Git 仓库初始化（可选）
init_git_repo() {
    if [ ! -d ".git" ]; then
        echo
        read -p "是否初始化 Git 仓库？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_step "初始化 Git 仓库..."
            
            git init
            git add .
            git commit -m "Initial commit: Jitsi Meet deployment configuration"
            
            echo
            read -p "请输入远程仓库地址 (可选，回车跳过): " REMOTE_REPO
            if [ ! -z "$REMOTE_REPO" ]; then
                git remote add origin "$REMOTE_REPO"
                log_info "已添加远程仓库: $REMOTE_REPO"
                log_info "稍后可以执行: git push -u origin main"
            fi
            
            log_success "Git 仓库初始化完成"
        fi
    fi
}

# 主函数
main() {
    show_banner
    
    # 检查参数
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Jitsi Meet 快速部署脚本"
        echo ""
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h     显示帮助信息"
        echo "  --skip-deps    跳过依赖安装"
        echo "  --no-ssl       跳过SSL证书申请"
        echo ""
        exit 0
    fi
    
    # 执行部署步骤
    check_root
    check_os
    
    if [ "$1" != "--skip-deps" ]; then
        install_dependencies
        install_docker
        install_nginx
        configure_firewall
    fi
    
    setup_env_file
    get_user_input
    update_config
    generate_secrets
    init_directories
    configure_nginx
    
    if [ "$1" != "--no-ssl" ]; then
        setup_ssl
    fi
    
    start_services
    start_monitoring
    
    # 等待服务稳定
    sleep 10
    
    verify_deployment
    show_completion
    init_git_repo
    
    log_success "Jitsi Meet 部署完成！"
}

# 执行主函数
main "$@"