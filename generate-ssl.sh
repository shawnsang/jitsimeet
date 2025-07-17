#!/bin/bash

# SSL证书生成脚本
# 用于生成自签名证书，仅供测试使用
# 生产环境请使用Let's Encrypt或购买正式证书

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
    log_info "检查依赖..."
    
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL 未安装，请先安装 OpenSSL"
        exit 1
    fi
    
    log_success "依赖检查完成"
}

# 创建SSL目录
create_ssl_directory() {
    log_info "创建SSL证书目录..."
    
    if [ ! -d "ssl" ]; then
        mkdir -p ssl
        log_success "SSL目录创建完成"
    else
        log_info "SSL目录已存在"
    fi
}

# 生成自签名证书
generate_self_signed_cert() {
    local domain="$1"
    
    log_info "为域名 ${domain} 生成自签名证书..."
    
    # 生成私钥
    openssl genrsa -out ssl/key.pem 2048
    
    # 生成证书签名请求配置
    cat > ssl/cert.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = CN
ST = Beijing
L = Beijing
O = Jitsi Meet
OU = IT Department
CN = ${domain}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${domain}
DNS.2 = *.${domain}
IP.1 = 127.0.0.1
EOF
    
    # 生成自签名证书
    openssl req -new -x509 -key ssl/key.pem -out ssl/cert.pem -days 365 -config ssl/cert.conf -extensions v3_req
    
    # 清理临时文件
    rm ssl/cert.conf
    
    log_success "自签名证书生成完成"
    log_warning "注意：自签名证书仅供测试使用，浏览器会显示安全警告"
    log_info "证书文件位置："
    log_info "  - 私钥：ssl/key.pem"
    log_info "  - 证书：ssl/cert.pem"
}

# 生成Let's Encrypt证书（使用certbot）
generate_letsencrypt_cert() {
    local domain="$1"
    local email="$2"
    
    log_info "为域名 ${domain} 申请Let's Encrypt证书..."
    
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot 未安装，请先安装 Certbot"
        log_info "Ubuntu/Debian: sudo apt install certbot"
        log_info "CentOS/RHEL: sudo yum install certbot"
        return 1
    fi
    
    # 使用standalone模式申请证书
    sudo certbot certonly --standalone \
        --email "${email}" \
        --agree-tos \
        --no-eff-email \
        -d "${domain}"
    
    # 复制证书到ssl目录
    sudo cp "/etc/letsencrypt/live/${domain}/fullchain.pem" ssl/cert.pem
    sudo cp "/etc/letsencrypt/live/${domain}/privkey.pem" ssl/key.pem
    sudo chown $(whoami):$(whoami) ssl/cert.pem ssl/key.pem
    
    log_success "Let's Encrypt证书申请完成"
    log_info "证书将在90天后过期，请设置自动续期"
}

# 显示帮助信息
show_help() {
    echo "SSL证书生成脚本"
    echo ""
    echo "用法："
    echo "  $0 self-signed <域名>          # 生成自签名证书"
    echo "  $0 letsencrypt <域名> <邮箱>   # 申请Let's Encrypt证书"
    echo "  $0 --help                      # 显示帮助信息"
    echo ""
    echo "示例："
    echo "  $0 self-signed meet.example.com"
    echo "  $0 letsencrypt meet.example.com admin@example.com"
    echo ""
    echo "注意："
    echo "  - 自签名证书仅供测试使用"
    echo "  - Let's Encrypt需要域名可以从公网访问"
    echo "  - 生产环境建议使用Let's Encrypt或购买正式证书"
}

# 主函数
main() {
    case "$1" in
        "self-signed")
            if [ -z "$2" ]; then
                log_error "请提供域名"
                show_help
                exit 1
            fi
            check_dependencies
            create_ssl_directory
            generate_self_signed_cert "$2"
            ;;
        "letsencrypt")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "请提供域名和邮箱地址"
                show_help
                exit 1
            fi
            check_dependencies
            create_ssl_directory
            generate_letsencrypt_cert "$2" "$3"
            ;;
        "--help"|-h)
            show_help
            ;;
        *)
            log_error "无效的参数"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"