#!/bin/bash

set -e

echo "🚀 Starting AI Conversation System Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required tools are installed
check_requirements() {
    echo "🔍 Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose is not installed${NC}"
        exit 1
    fi
    
    if ! command -v wrangler &> /dev/null; then
        echo -e "${YELLOW}⚠️  Wrangler (Cloudflare CLI) is not installed. Install with: npm install -g wrangler${NC}"
    fi
    
    if ! command -v vercel &> /dev/null; then
        echo -e "${YELLOW}⚠️  Vercel CLI is not installed. Install with: npm install -g vercel${NC}"
    fi
    
    echo -e "${GREEN}✅ Requirements check passed${NC}"
}

# Load environment variables
load_env() {
    echo "📋 Loading environment variables..."
    
    if [ -f .env ]; then
        export $(cat .env | grep -v '^#' | xargs)
        echo -e "${GREEN}✅ Environment variables loaded${NC}"
    else
        echo -e "${YELLOW}⚠️  No .env file found. Using defaults${NC}"
    fi
}

# Deploy Edge Gateway to Cloudflare
deploy_edge_gateway() {
    echo "🌐 Deploying Edge Gateway to Cloudflare..."
    
    if command -v wrangler &> /dev/null; then
        cd ../edge-gateway
        
        # Build the project
        echo "🔨 Building Edge Gateway..."
        npm run build
        
        # Deploy to Cloudflare
        echo "🚀 Deploying to Cloudflare..."
        wrangler deploy
        
        cd ../deployment
        echo -e "${GREEN}✅ Edge Gateway deployed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Skipping Edge Gateway deployment (Wrangler not installed)${NC}"
    fi
}

# Deploy Core API to Vercel
deploy_core_api() {
    echo "🔧 Deploying Core API to Vercel..."
    
    if command -v vercel &> /dev/null; then
        cd ../core-api
        
        # Deploy to Vercel
        echo "🚀 Deploying to Vercel..."
        vercel --prod
        
        cd ../deployment
        echo -e "${GREEN}✅ Core API deployed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Skipping Core API deployment (Vercel CLI not installed)${NC}"
    fi
}

# Deploy Model Router
deploy_model_router() {
    echo "🧠 Deploying Model Router..."
    
    cd ../model-router
    
    # Build the project
    echo "🔨 Building Model Router..."
    npm run build
    
    # Deploy to your preferred platform (e.g., Railway, Render, or keep local)
    echo "🚀 Model Router built successfully (deploy manually to your preferred platform)"
    
    cd ../deployment
    echo -e "${GREEN}✅ Model Router built successfully${NC}"
}

# Setup database
setup_database() {
    echo "🗄️  Setting up database..."
    
    # Check if PostgreSQL is running
    if docker ps | grep -q postgres; then
        echo "📊 Database is already running"
    else
        echo "🚀 Starting database services..."
        docker-compose up -d postgres redis
        
        # Wait for database to be ready
        echo "⏳ Waiting for database to be ready..."
        sleep 30
        
        # Run migrations
        echo "🔧 Running database migrations..."
        docker-compose exec -T postgres psql -U ai_user -d ai_conversation -f /docker-entrypoint-initdb.d/schema.sql
    fi
    
    echo -e "${GREEN}✅ Database setup completed${NC}"
}

# Start local services
start_local_services() {
    echo "🏠 Starting local services..."
    
    # Start all services
    docker-compose up -d
    
    echo -e "${GREEN}✅ Local services started${NC}"
}

# Health check
health_check() {
    echo "🏥 Performing health check..."
    
    # Wait for services to be ready
    sleep 10
    
    # Check Edge Gateway
    if curl -f http://localhost:8787/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Edge Gateway is healthy${NC}"
    else
        echo -e "${RED}❌ Edge Gateway health check failed${NC}"
    fi
    
    # Check Core API
    if curl -f http://localhost:3000/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Core API is healthy${NC}"
    else
        echo -e "${RED}❌ Core API health check failed${NC}"
    fi
    
    # Check Model Router
    if curl -f http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Model Router is healthy${NC}"
    else
        echo -e "${RED}❌ Model Router health check failed${NC}"
    fi
    
    # Check database
    if docker-compose exec -T postgres pg_isready -U ai_user > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Database is healthy${NC}"
    else
        echo -e "${RED}❌ Database health check failed${NC}"
    fi
}

# Main deployment function
main() {
    echo "🎯 AI Conversation System Deployment Script"
    echo "=========================================="
    
    check_requirements
    load_env
    
    # Ask user what to deploy
    echo ""
    echo "What would you like to deploy?"
    echo "1) Local development environment only"
    echo "2) Production deployment (Cloudflare + Vercel)"
    echo "3) Full deployment (local + production)"
    echo "4) Health check only"
    
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)
            echo "🏠 Setting up local development environment..."
            setup_database
            start_local_services
            health_check
            ;;
        2)
            echo "🚀 Deploying to production..."
            deploy_edge_gateway
            deploy_core_api
            deploy_model_router
            ;;
        3)
            echo "🌍 Full deployment..."
            deploy_edge_gateway
            deploy_core_api
            deploy_model_router
            setup_database
            start_local_services
            health_check
            ;;
        4)
            echo "🏥 Health check only..."
            health_check
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo "📊 Service URLs:"
    echo "   Edge Gateway: http://localhost:8787"
    echo "   Core API: http://localhost:3000"
    echo "   Model Router: http://localhost:3001"
    echo "   Prometheus: http://localhost:9090"
    echo "   Grafana: http://localhost:3000 (admin/admin)"
    echo ""
    echo "🔧 Next steps:"
    echo "   1. Configure your API keys in .env file"
    echo "   2. Update service URLs in your client applications"
    echo "   3. Test the endpoints with the provided examples"
}

# Run main function
main "$@" 