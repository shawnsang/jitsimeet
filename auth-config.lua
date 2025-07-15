-- Jitsi Meet 认证配置
-- 用于实现固定例会免认证和临时会议密码认证

-- 配置参数
local config = {
    -- 固定例会房间（免认证）
    public_rooms = {
        "daily-standup",      -- 每日站会
        "team-meeting",      -- 团队会议
        "weekly-review",     -- 周会
        "monthly-review",    -- 月会
        "all-hands",         -- 全员会议
    },
    
    -- 临时会议房间前缀（需要认证）
    private_room_prefix = "private-",
    
    -- 默认密码（可以通过环境变量覆盖）
    default_password = os.getenv("JITSI_DEFAULT_PASSWORD") or "meeting123",
    
    -- 管理员用户
    admin_users = {
        "admin@meet.jitsi",
        "moderator@meet.jitsi",
    },
    
    -- 会议室设置
    room_settings = {
        -- 最大参与者数量
        max_participants = 20,
        
        -- 会议超时时间（分钟）
        meeting_timeout = 120,
        
        -- 是否启用等候室
        enable_lobby = true,
        
        -- 是否启用录制
        enable_recording = false,
    }
}

-- 检查房间是否为公开房间
local function is_public_room(room_name)
    for _, public_room in ipairs(config.public_rooms) do
        if room_name == public_room then
            return true
        end
    end
    return false
end

-- 检查房间是否为私有房间
local function is_private_room(room_name)
    return string.sub(room_name, 1, string.len(config.private_room_prefix)) == config.private_room_prefix
end

-- 检查用户是否为管理员
local function is_admin_user(username)
    for _, admin in ipairs(config.admin_users) do
        if username == admin then
            return true
        end
    end
    return false
end

-- 验证密码
local function validate_password(provided_password, room_name)
    -- 对于私有房间，使用房间特定密码或默认密码
    local expected_password = config.default_password
    
    -- 可以根据房间名称设置特定密码
    if room_name == "private-important" then
        expected_password = "important123"
    elseif room_name == "private-executive" then
        expected_password = "exec456"
    end
    
    return provided_password == expected_password
end

-- 主认证函数
local function authenticate_user(username, password, room_name)
    -- 管理员用户始终允许访问
    if is_admin_user(username) then
        return true, "admin"
    end
    
    -- 公开房间无需认证
    if is_public_room(room_name) then
        return true, "guest"
    end
    
    -- 私有房间需要密码认证
    if is_private_room(room_name) then
        if password and validate_password(password, room_name) then
            return true, "authenticated"
        else
            return false, "invalid_password"
        end
    end
    
    -- 其他房间默认需要认证
    if password and validate_password(password, room_name) then
        return true, "authenticated"
    else
        return false, "authentication_required"
    end
end

-- 获取房间配置
local function get_room_config(room_name)
    local room_config = {
        max_participants = config.room_settings.max_participants,
        meeting_timeout = config.room_settings.meeting_timeout,
        enable_lobby = config.room_settings.enable_lobby,
        enable_recording = config.room_settings.enable_recording,
    }
    
    -- 公开房间的特殊配置
    if is_public_room(room_name) then
        room_config.enable_lobby = false  -- 公开房间不启用等候室
        room_config.auto_join = true      -- 自动加入
    end
    
    -- 私有房间的特殊配置
    if is_private_room(room_name) then
        room_config.enable_lobby = true   -- 私有房间启用等候室
        room_config.require_password = true
    end
    
    return room_config
end

-- 日志记录函数
local function log_access(username, room_name, success, user_type)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local status = success and "SUCCESS" or "FAILED"
    local log_entry = string.format(
        "[%s] %s - User: %s, Room: %s, Type: %s",
        timestamp, status, username or "anonymous", room_name, user_type or "unknown"
    )
    
    -- 这里可以将日志写入文件或发送到日志服务
    print(log_entry)
end

-- 房间创建钩子
local function on_room_created(room_name, creator)
    log_access(creator, room_name, true, "room_created")
    
    -- 应用房间配置
    local room_config = get_room_config(room_name)
    
    -- 这里可以设置房间的具体配置
    -- 例如：设置最大参与者数量、启用/禁用功能等
end

-- 用户加入钩子
local function on_user_joined(username, room_name)
    log_access(username, room_name, true, "user_joined")
end

-- 用户离开钩子
local function on_user_left(username, room_name)
    log_access(username, room_name, true, "user_left")
end

-- 导出函数
return {
    authenticate_user = authenticate_user,
    get_room_config = get_room_config,
    is_public_room = is_public_room,
    is_private_room = is_private_room,
    is_admin_user = is_admin_user,
    on_room_created = on_room_created,
    on_user_joined = on_user_joined,
    on_user_left = on_user_left,
    config = config
}