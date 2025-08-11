-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Create documents table for RAG
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    embedding VECTOR(1536), -- OpenAI embedding dimension
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    source_url TEXT,
    document_type VARCHAR(100),
    tags TEXT[]
);

-- Create conversations table
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(255) NOT NULL,
    title VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}',
    is_archived BOOLEAN DEFAULT FALSE
);

-- Create messages table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    model_used VARCHAR(100),
    tokens_used INTEGER,
    cost_estimate DECIMAL(10,6)
);

-- Create embeddings table for caching
CREATE TABLE IF NOT EXISTS embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    text_hash VARCHAR(64) UNIQUE NOT NULL,
    embedding VECTOR(1536) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    model VARCHAR(100) NOT NULL
);

-- Create usage tracking table
CREATE TABLE IF NOT EXISTS usage_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(255) NOT NULL,
    model VARCHAR(100) NOT NULL,
    provider VARCHAR(100) NOT NULL,
    tokens_input INTEGER NOT NULL,
    tokens_output INTEGER NOT NULL,
    cost DECIMAL(10,6) NOT NULL,
    request_type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

-- Create rate limiting table
CREATE TABLE IF NOT EXISTS rate_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(255) NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    request_count INTEGER DEFAULT 1,
    window_start TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_documents_embedding ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_documents_content_gin ON documents USING gin(to_tsvector('english', content));
CREATE INDEX IF NOT EXISTS idx_documents_metadata_gin ON documents USING gin(metadata);
CREATE INDEX IF NOT EXISTS idx_documents_tags_gin ON documents USING gin(tags);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_role ON messages(role);

CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(created_at);

CREATE INDEX IF NOT EXISTS idx_usage_tracking_user_id ON usage_tracking(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_tracking_created_at ON usage_tracking(created_at);
CREATE INDEX IF NOT EXISTS idx_usage_tracking_model ON usage_tracking(model);

CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint ON rate_limits(user_id, endpoint);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start ON rate_limits(window_start);

-- Create full-text search function
CREATE OR REPLACE FUNCTION search_documents(
    search_query TEXT,
    similarity_threshold FLOAT DEFAULT 0.7,
    max_results INTEGER DEFAULT 10,
    search_type VARCHAR(20) DEFAULT 'hybrid'
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    metadata JSONB,
    similarity_score FLOAT,
    search_rank FLOAT
) AS $$
BEGIN
    IF search_type = 'vector' THEN
        RETURN QUERY
        SELECT 
            d.id,
            d.content,
            d.metadata,
            d.embedding <=> (SELECT embedding FROM embeddings WHERE text_hash = md5(search_query) LIMIT 1) as similarity_score,
            0.0 as search_rank
        FROM documents d
        WHERE d.embedding IS NOT NULL
        ORDER BY d.embedding <=> (SELECT embedding FROM embeddings WHERE text_hash = md5(search_query) LIMIT 1)
        LIMIT max_results;
        
    ELSIF search_type = 'text' THEN
        RETURN QUERY
        SELECT 
            d.id,
            d.content,
            d.metadata,
            0.0 as similarity_score,
            ts_rank(to_tsvector('english', d.content), plainto_tsquery('english', search_query)) as search_rank
        FROM documents d
        WHERE to_tsvector('english', d.content) @@ plainto_tsquery('english', search_query)
        ORDER BY search_rank DESC
        LIMIT max_results;
        
    ELSE
        -- Hybrid search: combine vector and text search
        RETURN QUERY
        SELECT 
            d.id,
            d.content,
            d.metadata,
            COALESCE(d.embedding <=> (SELECT embedding FROM embeddings WHERE text_hash = md5(search_query) LIMIT 1), 0.0) as similarity_score,
            COALESCE(ts_rank(to_tsvector('english', d.content), plainto_tsquery('english', search_query)), 0.0) as search_rank
        FROM documents d
        WHERE (d.embedding IS NOT NULL OR to_tsvector('english', d.content) @@ plainto_tsquery('english', search_query))
        ORDER BY (COALESCE(d.embedding <=> (SELECT embedding FROM embeddings WHERE text_hash = md5(search_query) LIMIT 1), 1.0) + 
                 (1.0 - COALESCE(ts_rank(to_tsvector('english', d.content), plainto_tsquery('english', search_query)), 0.0))) / 2.0
        LIMIT max_results;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversations_updated_at BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function to clean up old rate limit records
CREATE OR REPLACE FUNCTION cleanup_rate_limits()
RETURNS void AS $$
BEGIN
    DELETE FROM rate_limits 
    WHERE window_start < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Create function to get user usage statistics
CREATE OR REPLACE FUNCTION get_user_usage_stats(
    user_id_param VARCHAR(255),
    days_back INTEGER DEFAULT 30
)
RETURNS TABLE (
    total_cost DECIMAL(10,6),
    total_tokens_input BIGINT,
    total_tokens_output BIGINT,
    requests_count BIGINT,
    avg_cost_per_request DECIMAL(10,6)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        SUM(ut.cost) as total_cost,
        SUM(ut.tokens_input) as total_tokens_input,
        SUM(ut.tokens_output) as total_tokens_output,
        COUNT(*) as requests_count,
        AVG(ut.cost) as avg_cost_per_request
    FROM usage_tracking ut
    WHERE ut.user_id = user_id_param
    AND ut.created_at >= NOW() - (days_back || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Insert sample data for testing
INSERT INTO documents (content, metadata, document_type, tags) VALUES
('Apple Watch is a smartwatch that pairs with your iPhone to provide health tracking, notifications, and apps.', 
 '{"source": "apple_docs", "category": "hardware"}', 
 'product_info', 
 ARRAY['apple', 'watch', 'smartwatch', 'health']),
 
('The Apple Watch Series 9 features advanced health monitoring including heart rate, blood oxygen, and ECG capabilities.', 
 '{"source": "apple_specs", "category": "health"}', 
 'product_info', 
 ARRAY['apple', 'watch', 'series9', 'health', 'monitoring']),
 
('watchOS is the operating system that powers Apple Watch, providing a seamless and intuitive user experience.', 
 '{"source": "apple_docs", "category": "software"}', 
 'product_info', 
 ARRAY['watchos', 'operating_system', 'apple', 'watch']);

-- Grant permissions (adjust as needed for your setup)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO your_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO your_user; 