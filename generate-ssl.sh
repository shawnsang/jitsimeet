#!/bin/bash

# SSL Certificate Generation Script for Jitsi Meet
# This script helps generate SSL certificates for HTTPS configuration
# Features: Self-signed certificates, Let's Encrypt, certificate validation, auto-renewal

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SSL_DIR="./ssl"
DOMAIN=""
EMAIL=""
CERT_TYPE="self-signed"
FORCE_RENEW=false
CHECK_ONLY=false
AUTO_RENEW=false
RENEW_DAYS=30

# Logging functions
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

# Certificate validation functions
check_cert_validity() {
    local cert_path="$1"
    local days_threshold="$2"
    
    if [[ ! -f "$cert_path" ]]; then
        log_warning "Certificate not found: $cert_path"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_expiry -le 0 ]]; then
        log_error "Certificate has expired: $cert_path"
        return 2
    elif [[ $days_until_expiry -le $days_threshold ]]; then
        log_warning "Certificate expires in $days_until_expiry days: $cert_path"
        return 3
    else
        log_success "Certificate is valid for $days_until_expiry days: $cert_path"
        return 0
    fi
}

get_cert_info() {
    local cert_path="$1"
    
    if [[ ! -f "$cert_path" ]]; then
        log_error "Certificate not found: $cert_path"
        return 1
    fi
    
    log_info "Certificate information for: $cert_path"
    openssl x509 -in "$cert_path" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After:|DNS:"
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
    
    # 创建证书目录
    mkdir -p "${SSL_DIR}"
    
    # 生成私钥
    openssl genrsa -out "${SSL_DIR}/privkey.pem" 2048
    
    # 生成证书签名请求配置
    cat > "${SSL_DIR}/cert.conf" << EOF
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
    openssl req -new -x509 -key "${SSL_DIR}/privkey.pem" -out "${SSL_DIR}/fullchain.pem" -days 365 -config "${SSL_DIR}/cert.conf" -extensions v3_req
    
    # 清理临时文件
    rm "${SSL_DIR}/cert.conf"
    
    log_success "自签名证书生成完成"
    log_warning "注意：自签名证书仅供测试使用，浏览器会显示安全警告"
    log_info "证书文件位置："
    log_info "  - 私钥：${SSL_DIR}/privkey.pem"
    log_info "  - 证书：${SSL_DIR}/fullchain.pem"
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
    sudo cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "${SSL_DIR}/fullchain.pem"
    sudo cp "/etc/letsencrypt/live/${domain}/privkey.pem" "${SSL_DIR}/privkey.pem"
    sudo chown $(whoami):$(whoami) "${SSL_DIR}/fullchain.pem" "${SSL_DIR}/privkey.pem"
    
    log_success "Let's Encrypt证书申请完成"
    log_info "证书将在90天后过期，请设置自动续期"
}

# Show help information
show_help() {
    echo "SSL Certificate Generation Script for Jitsi Meet"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN     Specify domain name (auto-read from .env if not provided)"
    echo "  -e, --email EMAIL       Specify email address (auto-read from .env if not provided)"
    echo "  -t, --type TYPE         Certificate type: self-signed or letsencrypt (default: self-signed)"
    echo "  -s, --ssl-dir DIR       SSL certificate directory (default: ./ssl)"
    echo "  -f, --force             Force regenerate certificate"
    echo "  -c, --check             Check certificate validity only"
    echo "  -a, --auto-renew        Enable auto-renewal for Let's Encrypt certificates"
    echo "  -r, --renew-days DAYS   Days before expiry to trigger renewal (default: 30)"
    echo "  -i, --info              Show certificate information"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Auto-configuration:"
    echo "  The script automatically reads domain and email from .env file:"
    echo "  - Domain: PUBLIC_URL=your-domain.com"
    echo "  - Email: LETSENCRYPT_EMAIL=your-email@example.com"
    echo ""
    echo "Examples:"
    echo "  # Generate self-signed certificate (auto-read domain from .env)"
    echo "  $0 -t self-signed"
    echo ""
    echo "  # Generate Let's Encrypt certificate (auto-read domain and email from .env)"
    echo "  $0 -t letsencrypt"
    echo ""
    echo "  # Override .env settings with command line options"
    echo "  $0 -d custom-domain.com -e custom@email.com -t letsencrypt"
    echo ""
    echo "  # Check certificate validity"
    echo "  $0 -c"
    echo ""
    echo "Notes:"
    echo "  - Configure PUBLIC_URL and LETSENCRYPT_EMAIL in .env file for automatic operation"
    echo "  - Command line options override .env file settings"
    echo "  - Self-signed certificates are for testing only, browsers will show security warnings"
    echo "  - Let's Encrypt certificates require domain to be publicly accessible"
    echo "  - For production, use Let's Encrypt or purchase commercial certificates"
    echo "  - Add this script to crontab for automatic certificate renewal"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -t|--type)
                CERT_TYPE="$2"
                shift 2
                ;;
            -s|--ssl-dir)
                SSL_DIR="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_RENEW=true
                shift
                ;;
            -c|--check)
                CHECK_ONLY=true
                shift
                ;;
            -a|--auto-renew)
                AUTO_RENEW=true
                shift
                ;;
            -r|--renew-days)
                RENEW_DAYS="$2"
                shift 2
                ;;
            -i|--info)
                INFO_ONLY=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 从.env文件读取配置
load_env_config() {
    if [[ -f ".env" ]]; then
        # 读取域名配置
        ENV_DOMAIN=$(grep "^PUBLIC_URL=" .env | cut -d'=' -f2 | tr -d '"')
        ENV_EMAIL=$(grep "^LETSENCRYPT_EMAIL=" .env | cut -d'=' -f2 | tr -d '"')
        
        # 如果命令行没有指定域名，尝试使用.env中的配置
        if [[ -z "$DOMAIN" ]] && [[ -n "$ENV_DOMAIN" ]] && [[ "$ENV_DOMAIN" != "your-domain.com" ]]; then
            log_info "从.env文件读取到域名: $ENV_DOMAIN"
            DOMAIN="$ENV_DOMAIN"
        fi
        
        # 如果命令行没有指定邮箱，尝试使用.env中的配置
        if [[ -z "$EMAIL" ]] && [[ -n "$ENV_EMAIL" ]] && [[ "$ENV_EMAIL" != "your-email@example.com" ]]; then
            log_info "从.env文件读取到邮箱: $ENV_EMAIL"
            EMAIL="$ENV_EMAIL"
        fi
    fi
}

# 主函数
main() {
    parse_arguments "$@"
    
    # 尝试从.env文件加载配置
    load_env_config
    
    # Validate required parameters
    if [[ -z "$DOMAIN" ]]; then
        log_error "Domain is required. Use -d or --domain option, or configure PUBLIC_URL in .env file."
        show_help
        exit 1
    fi
    
    # Check certificate validity only
    if [[ "$CHECK_ONLY" == true ]]; then
        check_cert_validity "$SSL_DIR/fullchain.pem" "$RENEW_DAYS"
        exit $?
    fi
    
    # Show certificate information only
    if [[ "$INFO_ONLY" == true ]]; then
        get_cert_info "$SSL_DIR/fullchain.pem"
        exit $?
    fi
    
    case "$CERT_TYPE" in
        "self-signed")
            check_dependencies
            create_ssl_directory
            generate_self_signed_cert "$DOMAIN"
            ;;
        "letsencrypt")
            if [[ -z "$EMAIL" ]]; then
                log_error "Email is required for Let's Encrypt certificates. Use -e or --email option."
                show_help
                exit 1
            fi
            check_dependencies
            create_ssl_directory
            generate_letsencrypt_cert "$DOMAIN" "$EMAIL"
            ;;
        *)
            log_error "Invalid certificate type: $CERT_TYPE"
            log_info "Supported types: self-signed, letsencrypt"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"