#!/bin/bash

# Jitsi Meet 自动重启脚本
# 用于监控服务状态并在异常时自动重启

set -e

# 配置文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/auto-restart.log"
PID_FILE="$SCRIPT_DIR/auto-restart.pid"
CONFIG_FILE="$SCRIPT_DIR/.env"

# 创建日志目录
mkdir -p "$SCRIPT_DIR/logs"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_warning() {
    log_message "WARNING" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}

# 配置参数
CHECK_INTERVAL=60           # 检查间隔（秒）
MAX_RESTART_ATTEMPTS=3      # 最大重启尝试次数
RESTART_COOLDOWN=300        # 重启冷却时间（秒）
HEALTH_CHECK_TIMEOUT=30     # 健康检查超时时间（秒）
MAX_CONSECUTIVE_FAILURES=3  # 最大连续失败次数

# 全局变量
RESTART_COUNT=0
LAST_RESTART_TIME=0
CONSECUTIVE_FAILURES=0
FAILURE_HISTORY=()

# 加载环境变量
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 获取公网URL
PUBLIC_URL=${PUBLIC_URL:-"http://localhost:8000"}
MONITOR_URL=${MONITOR_URL:-"http://localhost:3001"}

# 检查Docker服务状态
check_docker_service() {
    local service_name="$1"
    
    if command -v docker-compose &> /dev/null; then
        local status=$(docker-compose ps -q "$service_name" 2>/dev/null)
    else
        local status=$(docker compose ps -q "$service_name" 2>/dev/null)
    fi
    
    if [ -z "$status" ]; then
        return 1
    fi
    
    local container_status=$(docker inspect --format='{{.State.Status}}' "$status" 2>/dev/null)
    
    if [ "$container_status" = "running" ]; then
        return 0
    else
        return 1
    fi
}

# 检查HTTP服务状态
check_http_service() {
    local url="$1"
    local expected_code="$2"
    
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$HEALTH_CHECK_TIMEOUT" "$url" 2>/dev/null || echo "000")
    
    if [ "$response_code" = "$expected_code" ] || [ "$response_code" = "200" ] || [ "$response_code" = "301" ] || [ "$response_code" = "302" ]; then
        return 0
    else
        return 1
    fi
}

# 检查端口状态
check_port() {
    local host="$1"
    local port="$2"
    
    if timeout "$HEALTH_CHECK_TIMEOUT" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 综合健康检查
perform_health_check() {
    local failed_services=()
    
    # 检查Docker容器
    local containers=("web" "prosody" "jicofo" "jvb" "uptime-kuma")
    for container in "${containers[@]}"; do
        if ! check_docker_service "$container"; then
            failed_services+=("$container container")
        fi
    done
    
    # 检查HTTP服务
    if ! check_http_service "$PUBLIC_URL" "200"; then
        failed_services+=("Jitsi Meet web service")
    fi
    
    if ! check_http_service "$MONITOR_URL" "200"; then
        failed_services+=("Uptime Kuma service")
    fi
    
    # 检查关键端口
    if ! check_port "localhost" "10000"; then
        failed_services+=("JVB UDP port 10000")
    fi
    
    if ! check_port "localhost" "4443"; then
        failed_services+=("JVB TCP port 4443")
    fi
    
    # 返回失败的服务列表
    if [ ${#failed_services[@]} -eq 0 ]; then
        return 0
    else
        log_warning "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# 重启服务
restart_services() {
    local current_time=$(date +%s)
    
    # 检查冷却时间
    if [ $((current_time - LAST_RESTART_TIME)) -lt $RESTART_COOLDOWN ]; then
        log_warning "Still in cooldown period, skipping restart"
        return 1
    fi
    
    # 检查最大重启次数
    if [ $RESTART_COUNT -ge $MAX_RESTART_ATTEMPTS ]; then
        log_error "Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached"
        return 1
    fi
    
    log_info "Attempting to restart services (attempt $((RESTART_COUNT + 1))/$MAX_RESTART_ATTEMPTS)"
    
    # 执行重启
    cd "$SCRIPT_DIR"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose down
        sleep 10
        docker-compose up -d
    else
        docker compose down
        sleep 10
        docker compose up -d
    fi
    
    # 更新重启计数和时间
    RESTART_COUNT=$((RESTART_COUNT + 1))
    LAST_RESTART_TIME=$current_time
    
    log_success "Services restarted successfully"
    
    # 等待服务启动
    log_info "Waiting for services to start..."
    sleep 60
    
    # 验证重启是否成功
    if perform_health_check; then
        log_success "Health check passed after restart"
        RESTART_COUNT=0  # 重置重启计数
        CONSECUTIVE_FAILURES=0  # 重置连续失败计数
        return 0
    else
        log_error "Health check failed after restart"
        return 1
    fi
}

# 发送告警通知
send_alert() {
    local message="$1"
    local severity="$2"
    
    # 记录告警
    log_error "ALERT [$severity]: $message"
    
    # 这里可以添加其他告警方式，如邮件、Webhook等
    # 示例：发送到Webhook
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"Jitsi Meet Alert [$severity]: $message\"}" \
            >/dev/null 2>&1 || true
    fi
}

# 清理旧日志
cleanup_logs() {
    # 保留最近7天的日志
    find "$SCRIPT_DIR/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
}

# 主监控循环
monitor_loop() {
    log_info "Starting Jitsi Meet monitoring service"
    log_info "Check interval: ${CHECK_INTERVAL}s, Max restarts: $MAX_RESTART_ATTEMPTS"
    
    while true; do
        if perform_health_check; then
            if [ $CONSECUTIVE_FAILURES -gt 0 ]; then
                log_success "Services recovered after $CONSECUTIVE_FAILURES failures"
                CONSECUTIVE_FAILURES=0
            fi
        else
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            log_warning "Health check failed (consecutive failures: $CONSECUTIVE_FAILURES)"
            
            # 记录失败历史
            FAILURE_HISTORY+=($(date +%s))
            
            # 如果连续失败次数达到阈值，尝试重启
            if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                log_error "Maximum consecutive failures reached, attempting restart"
                
                if restart_services; then
                    send_alert "Services restarted successfully after $CONSECUTIVE_FAILURES failures" "INFO"
                else
                    send_alert "Failed to restart services after $CONSECUTIVE_FAILURES failures" "CRITICAL"
                fi
            fi
        fi
        
        # 清理旧的失败记录（保留最近1小时）
        local current_time=$(date +%s)
        local new_history=()
        for timestamp in "${FAILURE_HISTORY[@]}"; do
            if [ $((current_time - timestamp)) -lt 3600 ]; then
                new_history+=("$timestamp")
            fi
        done
        FAILURE_HISTORY=("${new_history[@]}")
        
        # 每小时清理一次日志
        if [ $((current_time % 3600)) -lt $CHECK_INTERVAL ]; then
            cleanup_logs
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# 停止监控
stop_monitor() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log_info "Monitoring service stopped"
        else
            log_warning "PID file exists but process not running"
            rm -f "$PID_FILE"
        fi
    else
        log_warning "PID file not found"
    fi
}

# 检查监控状态
check_monitor_status() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Monitoring service is running (PID: $pid)"
            return 0
        else
            echo "PID file exists but process not running"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "Monitoring service is not running"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo "Jitsi Meet 自动重启监控脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  start       启动监控服务"
    echo "  stop        停止监控服务"
    echo "  status      查看监控状态"
    echo "  check       执行一次健康检查"
    echo "  restart     手动重启服务"
    echo "  logs        查看监控日志"
    echo "  help        显示帮助信息"
}

# 主函数
main() {
    case "$1" in
        start)
            if check_monitor_status >/dev/null 2>&1; then
                echo "Monitoring service is already running"
                exit 1
            fi
            
            # 后台启动监控
            nohup "$0" monitor >/dev/null 2>&1 &
            echo $! > "$PID_FILE"
            echo "Monitoring service started"
            ;;
        stop)
            stop_monitor
            ;;
        status)
            check_monitor_status
            ;;
        check)
            if perform_health_check; then
                echo "All services are healthy"
            else
                echo "Some services are unhealthy"
                exit 1
            fi
            ;;
        restart)
            restart_services
            ;;
        logs)
            tail -f "$LOG_FILE"
            ;;
        monitor)
            # 内部命令，用于实际的监控循环
            monitor_loop
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            echo "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"