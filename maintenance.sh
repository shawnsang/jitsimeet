#!/bin/bash

# Jitsi Meet Maintenance Script
# This script provides automated maintenance tasks including:
# - Configuration backup and restore
# - Log rotation and cleanup
# - SSL certificate renewal
# - System updates and cleanup
# - Performance optimization

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="./backups"
LOG_RETENTION_DAYS=30
BACKUP_RETENTION_DAYS=90
MAX_LOG_SIZE="100M"
CONFIG_FILES=(".env" "docker-compose.yml" "nginx.conf" "auth-config.lua")

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

# Create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_success "Created backup directory: $BACKUP_DIR"
    fi
}

# Backup configuration files
backup_config() {
    log_header "Configuration Backup"
    
    create_backup_dir
    
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/config-backup-$timestamp.tar.gz"
    
    # Create list of files to backup
    local files_to_backup=()
    for file in "${CONFIG_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            files_to_backup+=("$file")
        else
            log_warning "Configuration file not found: $file"
        fi
    done
    
    if [[ ${#files_to_backup[@]} -eq 0 ]]; then
        log_error "No configuration files found to backup"
        return 1
    fi
    
    # Create backup archive
    tar -czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null
    
    if [[ -f "$backup_file" ]]; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Configuration backup created: $backup_file ($backup_size)"
        
        # Create a latest backup symlink
        ln -sf "$(basename "$backup_file")" "$BACKUP_DIR/latest-config-backup.tar.gz"
        log_info "Latest backup symlink updated"
    else
        log_error "Failed to create configuration backup"
        return 1
    fi
    
    echo
}

# Restore configuration from backup
restore_config() {
    log_header "Configuration Restore"
    
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        # Use latest backup if no file specified
        backup_file="$BACKUP_DIR/latest-config-backup.tar.gz"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Create backup of current configuration before restore
    log_info "Creating backup of current configuration before restore"
    backup_config
    
    # Extract backup
    log_info "Restoring configuration from: $backup_file"
    tar -xzf "$backup_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Configuration restored successfully"
        log_warning "Please restart services to apply restored configuration"
    else
        log_error "Failed to restore configuration"
        return 1
    fi
    
    echo
}

# Clean up old backups
cleanup_backups() {
    log_header "Backup Cleanup"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backup directory found, skipping cleanup"
        return
    fi
    
    local old_backups=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null)
    
    if [[ -n "$old_backups" ]]; then
        local count=$(echo "$old_backups" | wc -l)
        log_info "Found $count backup files older than $BACKUP_RETENTION_DAYS days"
        
        echo "$old_backups" | while read -r backup; do
            rm -f "$backup"
            log_info "Removed old backup: $(basename "$backup")"
        done
        
        log_success "Old backups cleaned up"
    else
        log_info "No old backups found to clean up"
    fi
    
    echo
}

# Log rotation and cleanup
log_cleanup() {
    log_header "Log Cleanup"
    
    local log_dirs=("/var/log/nginx" "./logs")
    local cleaned_files=0
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            log_info "Cleaning logs in: $log_dir"
            
            # Find and compress old log files
            local old_logs=$(find "$log_dir" -name "*.log" -mtime +7 -size +10M 2>/dev/null)
            if [[ -n "$old_logs" ]]; then
                echo "$old_logs" | while read -r logfile; do
                    if [[ -f "$logfile" ]] && [[ ! -f "$logfile.gz" ]]; then
                        gzip "$logfile"
                        log_info "Compressed: $(basename "$logfile")"
                        ((cleaned_files++))
                    fi
                done
            fi
            
            # Remove very old compressed logs
            local very_old_logs=$(find "$log_dir" -name "*.log.gz" -mtime +$LOG_RETENTION_DAYS 2>/dev/null)
            if [[ -n "$very_old_logs" ]]; then
                echo "$very_old_logs" | while read -r logfile; do
                    rm -f "$logfile"
                    log_info "Removed old log: $(basename "$logfile")"
                    ((cleaned_files++))
                done
            fi
        fi
    done
    
    if [[ $cleaned_files -gt 0 ]]; then
        log_success "Cleaned up $cleaned_files log files"
    else
        log_info "No log files needed cleanup"
    fi
    
    echo
}

# Docker system cleanup
docker_cleanup() {
    log_header "Docker System Cleanup"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker not available, skipping Docker cleanup"
        return
    fi
    
    # Show current disk usage
    log_info "Current Docker disk usage:"
    docker system df
    echo
    
    # Remove unused containers, networks, images, and build cache
    log_info "Removing unused Docker resources..."
    docker system prune -f
    
    # Remove unused volumes (be careful with this)
    log_info "Removing unused Docker volumes..."
    docker volume prune -f
    
    # Show disk usage after cleanup
    log_info "Docker disk usage after cleanup:"
    docker system df
    
    log_success "Docker cleanup completed"
    echo
}

# SSL certificate renewal check
ssl_renewal_check() {
    log_header "SSL Certificate Renewal Check"
    
    if [[ ! -f ".env" ]]; then
        log_warning "Environment file .env not found, skipping SSL renewal check"
        return
    fi
    
    source .env
    
    if [[ -z "$SSL_CERT_PATH" ]]; then
        log_warning "SSL certificate path not configured"
        return
    fi
    
    if [[ ! -f "$SSL_CERT_PATH" ]]; then
        log_warning "SSL certificate not found: $SSL_CERT_PATH"
        return
    fi
    
    # Check if certificate needs renewal
    if command -v openssl >/dev/null 2>&1; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$SSL_CERT_PATH" 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -le 30 ]]; then
                log_warning "SSL certificate expires in $days_until_expiry days"
                log_info "Consider renewing the certificate using ./generate-ssl.sh"
                
                # If it's a Let's Encrypt certificate, suggest auto-renewal
                if [[ "$SSL_CERT_PATH" == *"letsencrypt"* ]]; then
                    log_info "For Let's Encrypt certificates, you can use:"
                    log_info "  ./generate-ssl.sh -d $PUBLIC_URL -e your-email@example.com -t letsencrypt -a"
                fi
            else
                log_success "SSL certificate is valid for $days_until_expiry days"
            fi
        fi
    else
        log_warning "OpenSSL not available, cannot check certificate expiry"
    fi
    
    echo
}

# System update check
system_update_check() {
    log_header "System Update Check"
    
    # Check for available package updates (Ubuntu/Debian)
    if command -v apt >/dev/null 2>&1; then
        log_info "Checking for available package updates..."
        apt list --upgradable 2>/dev/null | grep -v "WARNING" | tail -n +2 | wc -l | xargs -I {} log_info "Available package updates: {}"
    fi
    
    # Check Docker image updates
    if command -v docker >/dev/null 2>&1; then
        log_info "Checking for Docker image updates..."
        local images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
        if [[ -n "$images" ]]; then
            echo "$images" | while read -r image; do
                docker pull "$image" >/dev/null 2>&1 && log_info "Updated: $image" || log_info "No update available: $image"
            done
        fi
    fi
    
    echo
}

# Performance optimization
performance_optimization() {
    log_header "Performance Optimization"
    
    # Clear system caches
    if [[ -w /proc/sys/vm/drop_caches ]]; then
        log_info "Clearing system caches..."
        sync
        echo 3 > /proc/sys/vm/drop_caches
        log_success "System caches cleared"
    else
        log_warning "Cannot clear system caches (insufficient permissions)"
    fi
    
    # Optimize Docker
    if command -v docker >/dev/null 2>&1; then
        log_info "Optimizing Docker..."
        docker system prune -f >/dev/null 2>&1
        log_success "Docker optimized"
    fi
    
    echo
}

# Show maintenance status
show_status() {
    log_header "Maintenance Status"
    
    # Show last backup
    if [[ -f "$BACKUP_DIR/latest-config-backup.tar.gz" ]]; then
        local backup_date=$(stat -c %y "$BACKUP_DIR/latest-config-backup.tar.gz" 2>/dev/null | cut -d' ' -f1)
        log_info "Last configuration backup: $backup_date"
    else
        log_warning "No configuration backup found"
    fi
    
    # Show disk usage
    log_info "Current disk usage:"
    df -h / | tail -1 | awk '{print "  Root filesystem: " $5 " used (" $3 "/" $2 ")"}'
    
    # Show system load
    log_info "System load: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Show memory usage
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
    log_info "Memory usage: $memory_usage"
    
    echo
}

# Show help
show_help() {
    echo "Jitsi Meet Maintenance Script"
    echo
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  backup              Create configuration backup"
    echo "  restore [file]      Restore configuration from backup"
    echo "  cleanup             Clean up logs and old backups"
    echo "  docker-cleanup      Clean up Docker system"
    echo "  ssl-check           Check SSL certificate renewal status"
    echo "  update-check        Check for system and Docker updates"
    echo "  optimize            Perform performance optimization"
    echo "  status              Show maintenance status"
    echo "  full                Run full maintenance (all tasks)"
    echo "  help                Show this help message"
    echo
    echo "Options:"
    echo "  --backup-dir DIR    Set backup directory (default: ./backups)"
    echo "  --log-retention N   Set log retention days (default: 30)"
    echo "  --backup-retention N Set backup retention days (default: 90)"
    echo
    echo "Examples:"
    echo "  $0 backup                    # Create configuration backup"
    echo "  $0 restore                   # Restore from latest backup"
    echo "  $0 restore backup.tar.gz     # Restore from specific backup"
    echo "  $0 full                      # Run full maintenance"
    echo "  $0 cleanup --log-retention 7 # Clean up with 7-day retention"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        backup)
            backup_config
            exit 0
            ;;
        restore)
            restore_config "$2"
            exit 0
            ;;
        cleanup)
            log_cleanup
            cleanup_backups
            exit 0
            ;;
        docker-cleanup)
            docker_cleanup
            exit 0
            ;;
        ssl-check)
            ssl_renewal_check
            exit 0
            ;;
        update-check)
            system_update_check
            exit 0
            ;;
        optimize)
            performance_optimization
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
        full)
            log_info "Starting full maintenance routine..."
            backup_config
            log_cleanup
            cleanup_backups
            docker_cleanup
            ssl_renewal_check
            performance_optimization
            show_status
            log_success "Full maintenance completed"
            exit 0
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --log-retention)
            LOG_RETENTION_DAYS="$2"
            shift 2
            ;;
        --backup-retention)
            BACKUP_RETENTION_DAYS="$2"
            shift 2
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
done

# If no command provided, show help
show_help