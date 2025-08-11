#!/bin/bash

# Database Setup Script for AI Conversation System
echo "🚀 Setting up AI Conversation System Database..."

# Check if PostgreSQL is running
if ! pg_isready -q; then
    echo "❌ PostgreSQL is not running. Please start PostgreSQL first."
    exit 1
fi

# Create database if it doesn't exist
echo "📊 Creating database 'ai_conversation'..."
createdb -U postgres ai_conversation 2>/dev/null || echo "Database already exists"

# Enable required extensions
echo "🔧 Enabling PostgreSQL extensions..."
psql -U postgres -d ai_conversation -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
psql -U postgres -d ai_conversation -c "CREATE EXTENSION IF NOT EXISTS \"pg_trgm\";"
psql -U postgres -d ai_conversation -c "CREATE EXTENSION IF NOT EXISTS \"vector\";"

# Run schema
echo "📋 Applying database schema..."
psql -U postgres -d ai_conversation -f schema.sql

echo "✅ Database setup completed!"
echo "📊 Database: ai_conversation"
echo "🔗 Connection: postgresql://postgres@localhost:5432/ai_conversation"
echo "🔑 Default user: postgres (no password for local development)"
