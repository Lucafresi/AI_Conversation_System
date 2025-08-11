#!/bin/bash

set -e

echo "🚀 Starting GPT-OSS Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GPT_OSS_20B_ENDPOINT=${GPT_OSS_20B_ENDPOINT:-"http://localhost:8000/v1"}
GPT_OSS_120B_ENDPOINT=${GPT_OSS_120B_ENDPOINT:-"http://localhost:8001/v1"}
MODEL_20B_PATH=${MODEL_20B_PATH:-"./models/gpt-oss-20b"}
MODEL_120B_PATH=${MODEL_120B_PATH:-"./models/gpt-oss-120b"}
SERVER_PORT_20B=${SERVER_PORT_20B:-8000}
SERVER_PORT_120B=${SERVER_PORT_120B:-8001}

# Check if required tools are installed
check_requirements() {
    echo "🔍 Checking requirements..."
    
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python 3 is not installed${NC}"
        exit 1
    fi
    
    if ! command -v pip3 &> /dev/null; then
        echo -e "${RED}❌ pip3 is not installed${NC}"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}❌ Git is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Requirements check passed${NC}"
}

# Install GPT-OSS dependencies
install_dependencies() {
    echo "📦 Installing GPT-OSS dependencies..."
    
    # Install vLLM with GPT-OSS support
    echo "Installing vLLM with GPT-OSS support..."
    pip3 install --pre vllm==0.10.1+gptoss \
        --extra-index-url https://wheels.vllm.ai/gpt-oss/ \
        --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
        --index-strategy unsafe-best-match
    
    # Install Ollama (alternative option)
    if ! command -v ollama &> /dev/null; then
        echo "Installing Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
    fi
    
    echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
}

# Download GPT-OSS models
download_models() {
    echo "📥 Downloading GPT-OSS models..."
    
    # Create models directory
    mkdir -p models
    
    # Download gpt-oss-20b
    if [ ! -d "$MODEL_20B_PATH" ]; then
        echo "Downloading gpt-oss-20b..."
        ollama pull gpt-oss:20b
        echo -e "${GREEN}✅ gpt-oss-20b downloaded${NC}"
    else
        echo -e "${YELLOW}⚠️  gpt-oss-20b already exists${NC}"
    fi
    
    # Download gpt-oss-120b (if hardware supports it)
    if [ ! -d "$MODEL_120B_PATH" ]; then
        echo "Checking hardware for gpt-oss-120b..."
        
        # Check available RAM
        total_ram=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$total_ram" -ge 80 ]; then
            echo "Downloading gpt-oss-120b (RAM: ${total_ram}GB)..."
            ollama pull gpt-oss:120b
            echo -e "${GREEN}✅ gpt-oss-120b downloaded${NC}"
        else
            echo -e "${YELLOW}⚠️  Skipping gpt-oss-120b (RAM: ${total_ram}GB < 80GB required)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  gpt-oss-120b already exists${NC}"
    fi
}

# Start GPT-OSS servers
start_servers() {
    echo "🚀 Starting GPT-OSS servers..."
    
    # Start gpt-oss-20b server
    echo "Starting gpt-oss-20b server on port $SERVER_PORT_20B..."
    nohup ollama serve gpt-oss:20b --port $SERVER_PORT_20B > logs/gpt-oss-20b.log 2>&1 &
    echo $! > pids/gpt-oss-20b.pid
    
    # Start gpt-oss-120b server if available
    if ollama list | grep -q "gpt-oss:120b"; then
        echo "Starting gpt-oss-120b server on port $SERVER_PORT_120B..."
        nohup ollama serve gpt-oss:120b --port $SERVER_PORT_120B > logs/gpt-oss-120b.log 2>&1 &
        echo $! > pids/gpt-oss-120b.pid
    fi
    
    # Wait for servers to start
    echo "Waiting for servers to start..."
    sleep 10
    
    echo -e "${GREEN}✅ GPT-OSS servers started${NC}"
}

# Alternative: Start with vLLM (for GPU servers)
start_vllm_servers() {
    echo "🚀 Starting GPT-OSS servers with vLLM..."
    
    # Check if CUDA is available
    if command -v nvidia-smi &> /dev/null; then
        echo "CUDA detected, using vLLM..."
        
        # Start gpt-oss-20b with vLLM
        echo "Starting gpt-oss-20b with vLLM on port $SERVER_PORT_20B..."
        nohup vllm serve openai/gpt-oss-20b --host 0.0.0.0 --port $SERVER_PORT_20B > logs/vllm-20b.log 2>&1 &
        echo $! > pids/vllm-20b.pid
        
        # Start gpt-oss-120b with vLLM if available
        if [ -d "$MODEL_120B_PATH" ]; then
            echo "Starting gpt-oss-120b with vLLM on port $SERVER_PORT_120B..."
            nohup vllm serve openai/gpt-oss-120b --host 0.0.0.0 --port $SERVER_PORT_120B > logs/vllm-120b.log 2>&1 &
            echo $! > pids/vllm-120b.pid
        fi
        
    else
        echo "CUDA not detected, using Ollama..."
        start_servers
    fi
    
    echo -e "${GREEN}✅ GPT-OSS servers started${NC}"
}

# Test GPT-OSS endpoints
test_endpoints() {
    echo "🧪 Testing GPT-OSS endpoints..."
    
    # Test gpt-oss-20b
    echo "Testing gpt-oss-20b endpoint..."
    if curl -s -f "http://localhost:$SERVER_PORT_20B/health" > /dev/null; then
        echo -e "${GREEN}✅ gpt-oss-20b endpoint is healthy${NC}"
    else
        echo -e "${RED}❌ gpt-oss-20b endpoint is not responding${NC}"
        return 1
    fi
    
    # Test gpt-oss-120b if available
    if ollama list | grep -q "gpt-oss:120b"; then
        echo "Testing gpt-oss-120b endpoint..."
        if curl -s -f "http://localhost:$SERVER_PORT_120B/health" > /dev/null; then
            echo -e "${GREEN}✅ gpt-oss-120b endpoint is healthy${NC}"
        else
            echo -e "${RED}❌ gpt-oss-120b endpoint is not responding${NC}"
            return 1
        fi
    fi
    
    # Test chat completion
    echo "Testing chat completion..."
    test_response=$(curl -s -X POST "http://localhost:$SERVER_PORT_20B/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-oss-20b",
            "messages": [{"role": "user", "content": "Hello! Say hi back."}],
            "max_tokens": 50
        }')
    
    if echo "$test_response" | grep -q "choices"; then
        echo -e "${GREEN}✅ Chat completion test passed${NC}"
        echo "Response: $(echo "$test_response" | jq -r '.choices[0].message.content' 2>/dev/null || echo 'Response received')"
    else
        echo -e "${RED}❌ Chat completion test failed${NC}"
        echo "Response: $test_response"
        return 1
    fi
    
    return 0
}

# Create necessary directories
setup_directories() {
    echo "📁 Setting up directories..."
    
    mkdir -p logs pids models
    echo -e "${GREEN}✅ Directories created${NC}"
}

# Stop servers
stop_servers() {
    echo "🛑 Stopping GPT-OSS servers..."
    
    if [ -f "pids/gpt-oss-20b.pid" ]; then
        kill $(cat pids/gpt-oss-20b.pid) 2>/dev/null || true
        rm pids/gpt-oss-20b.pid
    fi
    
    if [ -f "pids/gpt-oss-120b.pid" ]; then
        kill $(cat pids/gpt-oss-120b.pid) 2>/dev/null || true
        rm pids/gpt-oss-120b.pid
    fi
    
    if [ -f "pids/vllm-20b.pid" ]; then
        kill $(cat pids/vllm-20b.pid) 2>/dev/null || true
        rm pids/vllm-20b.pid
    fi
    
    if [ -f "pids/vllm-120b.pid" ]; then
        kill $(cat pids/vllm-120b.pid) 2>/dev/null || true
        rm pids/vllm-120b.pid
    fi
    
    echo -e "${GREEN}✅ Servers stopped${NC}"
}

# Show status
show_status() {
    echo "📊 GPT-OSS Server Status"
    echo "========================"
    
    echo -e "\n${BLUE}Models Available:${NC}"
    ollama list | grep "gpt-oss" || echo "No GPT-OSS models found"
    
    echo -e "\n${BLUE}Server Status:${NC}"
    if [ -f "pids/gpt-oss-20b.pid" ]; then
        echo -e "gpt-oss-20b: ${GREEN}RUNNING${NC} (PID: $(cat pids/gpt-oss-20b.pid))"
    else
        echo -e "gpt-oss-20b: ${RED}STOPPED${NC}"
    fi
    
    if [ -f "pids/gpt-oss-120b.pid" ]; then
        echo -e "gpt-oss-120b: ${GREEN}RUNNING${NC} (PID: $(cat pids/gpt-oss-120b.pid))"
    else
        echo -e "gpt-oss-120b: ${RED}STOPPED${NC}"
    fi
    
    echo -e "\n${BLUE}Endpoints:${NC}"
    echo "gpt-oss-20b: http://localhost:$SERVER_PORT_20B"
    echo "gpt-oss-120b: http://localhost:$SERVER_PORT_120B"
    
    echo -e "\n${BLUE}Environment Variables:${NC}"
    echo "GPT_OSS_20B_ENDPOINT: $GPT_OSS_20B_ENDPOINT"
    echo "GPT_OSS_120B_ENDPOINT: $GPT_OSS_120B_ENDPOINT"
}

# Main deployment function
main() {
    echo "🎯 GPT-OSS Deployment Script"
    echo "============================"
    
    # Parse command line arguments
    case "${1:-deploy}" in
        "deploy")
            echo "🚀 Deploying GPT-OSS..."
            check_requirements
            setup_directories
            install_dependencies
            download_models
            start_vllm_servers
            sleep 5
            test_endpoints
            ;;
        "start")
            echo "▶️  Starting GPT-OSS servers..."
            start_vllm_servers
            ;;
        "stop")
            echo "⏹️  Stopping GPT-OSS servers..."
            stop_servers
            ;;
        "restart")
            echo "🔄 Restarting GPT-OSS servers..."
            stop_servers
            sleep 2
            start_vllm_servers
            ;;
        "status")
            show_status
            ;;
        "test")
            echo "🧪 Testing GPT-OSS endpoints..."
            test_endpoints
            ;;
        "logs")
            echo "📋 Showing logs..."
            echo -e "\n${BLUE}gpt-oss-20b logs:${NC}"
            tail -20 logs/gpt-oss-20b.log 2>/dev/null || echo "No logs found"
            echo -e "\n${BLUE}gpt-oss-120b logs:${NC}"
            tail -20 logs/gpt-oss-120b.log 2>/dev/null || echo "No logs found"
            ;;
        *)
            echo "Usage: $0 {deploy|start|stop|restart|status|test|logs}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Full deployment (install, download, start)"
            echo "  start    - Start servers only"
            echo "  stop     - Stop servers only"
            echo "  restart  - Restart servers"
            echo "  status   - Show server status"
            echo "  test     - Test endpoints"
            echo "  logs     - Show recent logs"
            exit 1
            ;;
    esac
    
    if [ "$1" = "deploy" ]; then
        echo ""
        echo -e "${GREEN}🎉 GPT-OSS deployment completed successfully!${NC}"
        echo ""
        echo "📊 Next steps:"
        echo "   1. Update your .env file with:"
        echo "      GPT_OSS_20B_ENDPOINT=http://localhost:$SERVER_PORT_20B"
        echo "      GPT_OSS_120B_ENDPOINT=http://localhost:$SERVER_PORT_120B"
        echo "   2. Restart your AI Conversation System"
        echo "   3. Test with: $0 test"
        echo ""
        echo "🔧 Management commands:"
        echo "   Status: $0 status"
        echo "   Logs: $0 logs"
        echo "   Restart: $0 restart"
        echo "   Stop: $0 stop"
    fi
}

# Cleanup on exit
trap 'echo -e "\n${YELLOW}⚠️  Received interrupt signal${NC}"; stop_servers; exit 1' INT TERM

# Run main function
main "$@" 