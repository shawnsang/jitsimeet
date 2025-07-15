-- Jitsi Meet PostgreSQL 初始化脚本
-- 用于存储会议记录、用户会话、统计数据等

-- 创建数据库扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- 会议记录表
CREATE TABLE IF NOT EXISTS conferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_name VARCHAR(255) NOT NULL,
    room_jid VARCHAR(255) NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER,
    participant_count INTEGER DEFAULT 0,
    max_participants INTEGER DEFAULT 0,
    recording_enabled BOOLEAN DEFAULT FALSE,
    recording_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 参与者记录表
CREATE TABLE IF NOT EXISTS participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conference_id UUID REFERENCES conferences(id) ON DELETE CASCADE,
    user_id VARCHAR(255),
    display_name VARCHAR(255),
    email VARCHAR(255),
    join_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    leave_time TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER,
    is_moderator BOOLEAN DEFAULT FALSE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 会议统计表
CREATE TABLE IF NOT EXISTS conference_stats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conference_id UUID REFERENCES conferences(id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    participant_count INTEGER DEFAULT 0,
    audio_streams INTEGER DEFAULT 0,
    video_streams INTEGER DEFAULT 0,
    bitrate_upload BIGINT DEFAULT 0,
    bitrate_download BIGINT DEFAULT 0,
    packet_loss_rate DECIMAL(5,4) DEFAULT 0,
    jitter_ms INTEGER DEFAULT 0,
    rtt_ms INTEGER DEFAULT 0
);

-- 用户会话表（用于Redis备份）
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id VARCHAR(255) UNIQUE NOT NULL,
    user_id VARCHAR(255),
    user_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE
);

-- 系统配置表
CREATE TABLE IF NOT EXISTS system_config (
    id SERIAL PRIMARY KEY,
    config_key VARCHAR(255) UNIQUE NOT NULL,
    config_value TEXT,
    config_type VARCHAR(50) DEFAULT 'string',
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 录制文件表
CREATE TABLE IF NOT EXISTS recordings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conference_id UUID REFERENCES conferences(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    duration_seconds INTEGER,
    format VARCHAR(50),
    status VARCHAR(50) DEFAULT 'processing',
    download_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 系统日志表
CREATE TABLE IF NOT EXISTS system_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    log_level VARCHAR(20) NOT NULL,
    component VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_id VARCHAR(255)
);

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_conferences_room_name ON conferences(room_name);
CREATE INDEX IF NOT EXISTS idx_conferences_start_time ON conferences(start_time);
CREATE INDEX IF NOT EXISTS idx_conferences_created_at ON conferences(created_at);

CREATE INDEX IF NOT EXISTS idx_participants_conference_id ON participants(conference_id);
CREATE INDEX IF NOT EXISTS idx_participants_user_id ON participants(user_id);
CREATE INDEX IF NOT EXISTS idx_participants_join_time ON participants(join_time);

CREATE INDEX IF NOT EXISTS idx_conference_stats_conference_id ON conference_stats(conference_id);
CREATE INDEX IF NOT EXISTS idx_conference_stats_timestamp ON conference_stats(timestamp);

CREATE INDEX IF NOT EXISTS idx_user_sessions_session_id ON user_sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_system_config_key ON system_config(config_key);

CREATE INDEX IF NOT EXISTS idx_recordings_conference_id ON recordings(conference_id);
CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status);
CREATE INDEX IF NOT EXISTS idx_recordings_created_at ON recordings(created_at);

CREATE INDEX IF NOT EXISTS idx_system_logs_timestamp ON system_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_system_logs_component ON system_logs(component);
CREATE INDEX IF NOT EXISTS idx_system_logs_log_level ON system_logs(log_level);

-- 创建更新时间触发器函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要的表添加更新时间触发器
CREATE TRIGGER update_conferences_updated_at BEFORE UPDATE ON conferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_sessions_updated_at BEFORE UPDATE ON user_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_system_config_updated_at BEFORE UPDATE ON system_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_recordings_updated_at BEFORE UPDATE ON recordings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 插入默认系统配置
INSERT INTO system_config (config_key, config_value, config_type, description) VALUES
('max_participants_per_room', '100', 'integer', '每个会议室最大参与者数量'),
('recording_enabled', 'true', 'boolean', '是否启用录制功能'),
('max_recording_duration', '7200', 'integer', '最大录制时长（秒）'),
('session_timeout', '86400', 'integer', '用户会话超时时间（秒）'),
('log_retention_days', '30', 'integer', '日志保留天数'),
('stats_collection_interval', '30', 'integer', '统计数据收集间隔（秒）')
ON CONFLICT (config_key) DO NOTHING;

-- 创建清理过期数据的函数
CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS void AS $$
BEGIN
    -- 清理过期的用户会话
    DELETE FROM user_sessions 
    WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- 清理过期的日志（根据配置的保留天数）
    DELETE FROM system_logs 
    WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '1 day' * (
        SELECT COALESCE(config_value::integer, 30) 
        FROM system_config 
        WHERE config_key = 'log_retention_days'
    );
    
    -- 清理超过90天的统计数据
    DELETE FROM conference_stats 
    WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '90 days';
    
    RAISE NOTICE 'Expired data cleanup completed';
END;
$$ LANGUAGE plpgsql;

-- 创建数据库用户权限
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO jitsi;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO jitsi;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO jitsi;

-- 记录初始化完成
INSERT INTO system_logs (log_level, component, message) VALUES
('INFO', 'DATABASE', 'PostgreSQL database initialized successfully');

COMMIT;