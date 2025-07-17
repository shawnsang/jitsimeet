#!/bin/bash

# Jitsi Meet Health Check and Monitoring Script
# This script performs comprehensive health checks on all Jitsi Meet services
# and provides detailed status reports with recommendations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
HEALTH_CHECK_TIMEOUT=30
SSL_EXPIRY_WARNING_DAYS=30
LOG_RETENTION_DAYS=7
MAX_CPU_USAGE=80
MAX_MEMORY_USAGE=80
MAX_DISK_USAGE=85

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

log_header() {
    echo -e "${PURPLE}[SECTION]${NC} $1"
    echo "==========================================="
}

# Check if Docker and Docker Compose are available
check_dependencies() {
    log_header "Checking Dependencies"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        return 1
    else
        log_success "Docker is available"
        docker --version
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "Docker Compose is not installed or not in PATH"
        return 1
    else
        log_success "Docker Compose is available"
        docker-compose --version
    fi
    
    echo
}

# Check system resources
check_system_resources() {
    log_header "System Resource Check"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if (( $(echo "$cpu_usage > $MAX_CPU_USAGE" | bc -l) )); then
        log_warning "High CPU usage: ${cpu_usage}%"
    else
        log_success "CPU usage: ${cpu_usage}%"
    fi
    
    # Memory usage
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$(( used_mem * 100 / total_mem ))
    
    if [[ $memory_usage -gt $MAX_MEMORY_USAGE ]]; then
        log_warning "High memory usage: ${memory_usage}%"
    else
        log_success "Memory usage: ${memory_usage}%"
    fi
    
    # Disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    if [[ $disk_usage -gt $MAX_DISK_USAGE ]]; then
        log_warning "High disk usage: ${disk_usage}%"
    else
        log_success "Disk usage: ${disk_usage}%"
    fi
    
    echo
}

# Check Docker containers status
check_containers() {
    log_header "Docker Containers Status"
    
    local containers=("nginx" "prosody" "jicofo" "jvb" "uptime-kuma")
    local all_healthy=true
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
            local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2}')
            if [[ $status == "Up" ]]; then
                log_success "$container: Running"
            else
                log_warning "$container: $status"
                all_healthy=false
            fi
        else
            log_error "$container: Not found or stopped"
            all_healthy=false
        fi
    done
    
    if [[ $all_healthy == true ]]; then
        log_success "All containers are running properly"
    else
        log_warning "Some containers have issues"
    fi
    
    echo
}

# Check SSL certificates
check_ssl_certificates() {
    log_header "SSL Certificate Check"
    
    if [[ ! -f ".env" ]]; then
        log_warning "Environment file .env not found, skipping SSL check"
        return
    fi
    
    source .env
    
    if [[ -z "$SSL_CERT_PATH" ]] || [[ -z "$SSL_KEY_PATH" ]]; then
        log_warning "SSL certificate paths not configured"
        return
    fi
    
    if [[ ! -f "$SSL_CERT_PATH" ]]; then
        log_error "SSL certificate not found: $SSL_CERT_PATH"
        return
    fi
    
    if [[ ! -f "$SSL_KEY_PATH" ]]; then
        log_error "SSL private key not found: $SSL_KEY_PATH"
        return
    fi
    
    # Check certificate validity
    if command -v openssl >/dev/null 2>&1; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$SSL_CERT_PATH" 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -le 0 ]]; then
                log_error "SSL certificate has expired"
            elif [[ $days_until_expiry -le $SSL_EXPIRY_WARNING_DAYS ]]; then
                log_warning "SSL certificate expires in $days_until_expiry days"
            else
                log_success "SSL certificate is valid for $days_until_expiry days"
            fi
        fi
    else
        log_warning "OpenSSL not available, cannot check certificate validity"
    fi
    
    echo
}

# Check service connectivity
check_service_connectivity() {
    log_header "Service Connectivity Check"
    
    if [[ ! -f ".env" ]]; then
        log_warning "Environment file .env not found, skipping connectivity check"
        return
    fi
    
    source .env
    
    # Check HTTPS endpoint
    if [[ -n "$PUBLIC_URL" ]]; then
        if curl -s --max-time $HEALTH_CHECK_TIMEOUT "https://$PUBLIC_URL" >/dev/null 2>&1; then
            log_success "HTTPS endpoint is accessible: https://$PUBLIC_URL"
        else
            log_error "HTTPS endpoint is not accessible: https://$PUBLIC_URL"
        fi
    fi
    
    # Check monitoring endpoint
    if [[ -n "$MONITOR_URL" ]]; then
        if curl -s --max-time $HEALTH_CHECK_TIMEOUT "https://$MONITOR_URL" >/dev/null 2>&1; then
            log_success "Monitoring endpoint is accessible: https://$MONITOR_URL"
        else
            log_warning "Monitoring endpoint is not accessible: https://$MONITOR_URL"
        fi
    fi
    
    echo
}

# Check log files and disk usage
check_logs() {
    log_header "Log Files Check"
    
    local log_dirs=("/var/log/nginx" "./logs")
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            local log_size=$(du -sh "$log_dir" 2>/dev/null | cut -f1)
            log_info "Log directory $log_dir size: $log_size"
            
            # Check for old log files
            local old_logs=$(find "$log_dir" -name "*.log*" -mtime +$LOG_RETENTION_DAYS 2>/dev/null | wc -l)
            if [[ $old_logs -gt 0 ]]; then
                log_warning "Found $old_logs log files older than $LOG_RETENTION_DAYS days in $log_dir"
            fi
        fi
    done
    
    echo
}

# Generate health report
generate_report() {
    log_header "Health Check Summary"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="health-report-$(date '+%Y%m%d-%H%M%S').txt"
    
    {
        echo "Jitsi Meet Health Check Report"
        echo "Generated: $timestamp"
        echo "======================================"
        echo
        
        echo "System Information:"
        echo "- Hostname: $(hostname)"
        echo "- Uptime: $(uptime -p)"
        echo "- Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo
        
        echo "Docker Information:"
        docker system df
        echo
        
        echo "Container Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
        
        echo "Recent Container Logs (last 50 lines):"
        for container in nginx prosody jicofo jvb; do
            if docker ps --format "{{.Names}}" | grep -q "$container"; then
                echo "--- $container ---"
                docker logs --tail 50 "$container" 2>&1 | tail -20
                echo
            fi
        done
        
    } > "$report_file"
    
    log_success "Health report generated: $report_file"
    echo
}

# Main function
main() {
    echo "Jitsi Meet Health Check Script"
    echo "=============================="
    echo "Started at: $(date)"
    echo
    
    check_dependencies
    check_system_resources
    check_containers
    check_ssl_certificates
    check_service_connectivity
    check_logs
    generate_report
    
    log_success "Health check completed at: $(date)"
}

# Show help
show_help() {
    echo "Jitsi Meet Health Check Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -q, --quick             Quick check (containers only)"
    echo "  -r, --report-only       Generate report only"
    echo "  -t, --timeout SECONDS   Set health check timeout (default: 30)"
    echo
    echo "Examples:"
    echo "  $0                      # Full health check"
    echo "  $0 -q                   # Quick check"
    echo "  $0 -t 60                # Set 60 second timeout"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quick)
            check_dependencies
            check_containers
            exit 0
            ;;
        -r|--report-only)
            generate_report
            exit 0
            ;;
        -t|--timeout)
            HEALTH_CHECK_TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main