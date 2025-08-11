#!/usr/bin/env python3
"""
AI Conversation System - Test Script
Testa tutti i componenti del sistema
"""

import requests
import json
import time
import sys
from typing import Dict, Any

class AISystemTester:
    def __init__(self, base_urls: Dict[str, str]):
        self.base_urls = base_urls
        self.results = {}
        
    def test_endpoint(self, service: str, endpoint: str, method: str = "GET", 
                     data: Dict[str, Any] = None, headers: Dict[str, str] = None) -> bool:
        """Testa un endpoint specifico"""
        try:
            url = f"{self.base_urls[service]}{endpoint}"
            
            if method == "GET":
                response = requests.get(url, headers=headers, timeout=10)
            elif method == "POST":
                response = requests.post(url, json=data, headers=headers, timeout=10)
            else:
                print(f"❌ Method {method} not supported")
                return False
            
            if response.status_code == 200:
                print(f"✅ {service} {endpoint}: OK")
                return True
            else:
                print(f"❌ {service} {endpoint}: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"❌ {service} {endpoint}: Connection error - {e}")
            return False
        except Exception as e:
            print(f"❌ {service} {endpoint}: Unexpected error - {e}")
            return False
    
    def test_health_endpoints(self) -> bool:
        """Testa tutti gli endpoint di health check"""
        print("🏥 Testing Health Endpoints...")
        
        success = True
        
        # Test Edge Gateway health
        if not self.test_endpoint("edge_gateway", "/health"):
            success = False
            
        # Test Core API health
        if not self.test_endpoint("core_api", "/api/health"):
            success = False
            
        # Test Model Router health
        if not self.test_endpoint("model_router", "/health"):
            success = False
            
        return success
    
    def test_chat_endpoint(self) -> bool:
        """Testa l'endpoint di chat"""
        print("💬 Testing Chat Endpoint...")
        
        test_message = {
            "messages": [
                {"role": "user", "content": "Hello! This is a test message."}
            ],
            "quality": "auto",
            "stream": False
        }
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer test-token"
        }
        
        return self.test_endpoint("edge_gateway", "/chat", "POST", test_message, headers)
    
    def test_rag_endpoint(self) -> bool:
        """Testa l'endpoint RAG"""
        print("🔍 Testing RAG Endpoint...")
        
        test_query = {
            "query": "Apple Watch features",
            "limit": 3,
            "search_type": "hybrid"
        }
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer test-token"
        }
        
        return self.test_endpoint("edge_gateway", "/rag/query", "POST", test_query, headers)
    
    def test_rate_limiting(self) -> bool:
        """Testa il rate limiting"""
        print("🚦 Testing Rate Limiting...")
        
        # Invia più richieste per testare il rate limiting
        success = True
        rate_limit_hit = False
        
        for i in range(105):  # Più del limite di 100/min
            response = requests.post(
                f"{self.base_urls['edge_gateway']}/chat",
                json={"messages": [{"role": "user", "content": f"Test message {i}"}]},
                headers={"Content-Type": "application/json", "Authorization": "Bearer test-token"},
                timeout=5
            )
            
            if response.status_code == 429:
                rate_limit_hit = True
                print(f"✅ Rate limit hit at request {i+1}")
                break
            elif response.status_code != 200:
                print(f"❌ Unexpected status code: {response.status_code}")
                success = False
                break
                
            time.sleep(0.1)  # Piccola pausa tra le richieste
        
        if not rate_limit_hit:
            print("❌ Rate limiting not working properly")
            success = False
            
        return success
    
    def test_streaming(self) -> bool:
        """Testa lo streaming delle risposte"""
        print("🌊 Testing Streaming...")
        
        try:
            response = requests.post(
                f"{self.base_urls['edge_gateway']}/chat",
                json={
                    "messages": [{"role": "user", "content": "Tell me a short story"}],
                    "stream": True
                },
                headers={"Content-Type": "application/json", "Authorization": "Bearer test-token"},
                stream=True,
                timeout=30
            )
            
            if response.status_code == 200:
                content_type = response.headers.get('content-type', '')
                if 'text/event-stream' in content_type:
                    print("✅ Streaming endpoint responding correctly")
                    return True
                else:
                    print(f"❌ Unexpected content type: {content_type}")
                    return False
            else:
                print(f"❌ Streaming failed with status: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Streaming test failed: {e}")
            return False
    
    def test_database_connection(self) -> bool:
        """Testa la connessione al database (se accessibile)"""
        print("🗄️  Testing Database Connection...")
        
        # Questo test richiede accesso diretto al database
        # Per ora, testiamo indirettamente tramite l'API
        try:
            response = requests.get(f"{self.base_urls['core_api']}/api/health", timeout=10)
            if response.status_code == 200:
                health_data = response.json()
                if health_data.get('checks', {}).get('database', {}).get('status') == 'healthy':
                    print("✅ Database connection healthy")
                    return True
                else:
                    print("❌ Database connection unhealthy")
                    return False
            else:
                print(f"❌ Cannot check database health: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Database health check failed: {e}")
            return False
    
    def run_all_tests(self) -> Dict[str, bool]:
        """Esegue tutti i test"""
        print("🚀 Starting AI Conversation System Tests")
        print("=" * 50)
        
        tests = {
            "Health Endpoints": self.test_health_endpoints,
            "Chat Endpoint": self.test_chat_endpoint,
            "RAG Endpoint": self.test_rag_endpoint,
            "Rate Limiting": self.test_rate_limiting,
            "Streaming": self.test_streaming,
            "Database Connection": self.test_database_connection
        }
        
        for test_name, test_func in tests.items():
            print(f"\n🧪 Running: {test_name}")
            print("-" * 30)
            
            try:
                result = test_func()
                self.results[test_name] = result
            except Exception as e:
                print(f"❌ Test {test_name} crashed: {e}")
                self.results[test_name] = False
        
        return self.results
    
    def print_summary(self):
        """Stampa il riepilogo dei test"""
        print("\n" + "=" * 50)
        print("📊 TEST SUMMARY")
        print("=" * 50)
        
        passed = 0
        total = len(self.results)
        
        for test_name, result in self.results.items():
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{test_name}: {status}")
            if result:
                passed += 1
        
        print(f"\nOverall: {passed}/{total} tests passed")
        
        if passed == total:
            print("🎉 All tests passed! System is working correctly.")
        elif passed > total / 2:
            print("⚠️  Most tests passed, but there are some issues to fix.")
        else:
            print("🚨 Many tests failed. System needs attention.")
        
        return passed == total

def main():
    """Main function"""
    
    # Configurazione per test locali
    local_urls = {
        "edge_gateway": "http://localhost:8787",
        "core_api": "http://localhost:3000",
        "model_router": "http://localhost:3001"
    }
    
    # Configurazione per test di produzione (da modificare con i tuoi URL)
    production_urls = {
        "edge_gateway": "https://your-edge-gateway.workers.dev",
        "core_api": "https://your-core-api.vercel.app",
        "model_router": "https://your-model-router.railway.app"
    }
    
    # Scegli l'ambiente da testare
    print("🌍 Choose environment to test:")
    print("1) Local development")
    print("2) Production")
    
    choice = input("Enter your choice (1 or 2): ").strip()
    
    if choice == "2":
        urls = production_urls
        print("🚀 Testing production environment...")
    else:
        urls = local_urls
        print("🏠 Testing local environment...")
    
    # Verifica che i servizi siano raggiungibili
    print("\n🔍 Checking service availability...")
    for service, url in urls.items():
        try:
            response = requests.get(f"{url}/health", timeout=5)
            if response.status_code == 200:
                print(f"✅ {service}: {url}")
            else:
                print(f"⚠️  {service}: {url} (Status: {response.status_code})")
        except:
            print(f"❌ {service}: {url} (Unreachable)")
    
    # Esegui i test
    tester = AISystemTester(urls)
    results = tester.run_all_tests()
    
    # Stampa il riepilogo
    success = tester.print_summary()
    
    # Exit code per CI/CD
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 