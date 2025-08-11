# 🚀 AI Conversation System - Deployment Guide

## 🎯 Panoramica

Questo sistema di conversazione AI enterprise è composto da:
- **Edge Gateway** (Cloudflare Workers) - Gestione richieste e streaming
- **Core API** (Vercel Functions) - Logica di business e RAG
- **Model Router** (Node.js) - Routing intelligente tra modelli AI
- **Database** (PostgreSQL + pgvector) - Storage e ricerca vettoriale
- **Monitoring** (Prometheus + Grafana) - Osservabilità e metriche

## 📋 Prerequisiti

### Software Richiesto
- Docker e Docker Compose
- Node.js 18+
- npm o yarn

### Account e API Keys
- [Cloudflare](https://cloudflare.com) - Account gratuito per iniziare
- [OpenAI](https://openai.com) - API key per GPT-4
- [Anthropic](https://anthropic.com) - API key per Claude (opzionale)
- [Vercel](https://vercel.com) - Account gratuito per iniziare

## 🏗️ Architettura del Sistema

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   iOS Client    │───▶│  Edge Gateway    │───▶│   Core API      │
│                 │    │  (Cloudflare)    │    │   (Vercel)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  Model Router    │    │   Database      │
                       │  (Node.js)       │    │ (PostgreSQL)    │
                       └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │   AI Models      │
                       │ (OpenAI/Anthropic)│
                       └──────────────────┘
```

## 🚀 Deployment Step-by-Step

### Fase 1: Setup Locale

1. **Clona il repository e naviga nella directory**
   ```bash
   cd AI_Conversation_System/deployment
   ```

2. **Configura le variabili d'ambiente**
   ```bash
   cp env.example .env
   # Modifica .env con le tue API keys
   ```

3. **Avvia i servizi locali**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   # Scegli opzione 1 per ambiente locale
   ```

### Fase 2: Setup Database

1. **Verifica che PostgreSQL sia in esecuzione**
   ```bash
   docker ps | grep postgres
   ```

2. **Connetti al database**
   ```bash
   docker-compose exec postgres psql -U ai_user -d ai_conversation
   ```

3. **Verifica le tabelle**
   ```sql
   \dt
   SELECT * FROM documents LIMIT 3;
   ```

### Fase 3: Test Locale

1. **Test Edge Gateway**
   ```bash
   curl http://localhost:8787/health
   ```

2. **Test Core API**
   ```bash
   curl http://localhost:3000/api/health
   ```

3. **Test Model Router**
   ```bash
   curl http://localhost:3001/health
   ```

4. **Test Chat Endpoint**
   ```bash
   curl -X POST http://localhost:8787/chat \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer your-token" \
     -d '{
       "messages": [{"role": "user", "content": "Hello!"}],
       "quality": "auto"
     }'
   ```

## 🌐 Deployment in Produzione

### Edge Gateway (Cloudflare)

1. **Installa Wrangler CLI**
   ```bash
   npm install -g wrangler
   ```

2. **Login su Cloudflare**
   ```bash
   wrangler login
   ```

3. **Configura il progetto**
   ```bash
   cd ../edge-gateway
   wrangler config
   ```

4. **Deploy**
   ```bash
   wrangler deploy
   ```

### Core API (Vercel)

1. **Installa Vercel CLI**
   ```bash
   npm install -g vercel
   ```

2. **Login su Vercel**
   ```bash
   vercel login
   ```

3. **Deploy**
   ```bash
   cd ../core-api
   vercel --prod
   ```

### Model Router

1. **Build del progetto**
   ```bash
   cd ../model-router
   npm run build
   ```

2. **Deploy su piattaforma preferita**
   - Railway: `railway up`
   - Render: Connect GitHub repository
   - Heroku: `heroku create && git push heroku main`

## 🔧 Configurazione

### Variabili d'Ambiente Principali

```bash
# API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Database
DATABASE_URL=postgresql://user:pass@host:port/db

# JWT
JWT_SECRET=your-super-secret-jwt-key

# Service URLs
CORE_API_URL=https://your-api.vercel.app
```

### Configurazione CORS

Modifica `edge-gateway/src/index.ts` per aggiungere i tuoi domini:

```typescript
const allowedOrigins = [
  'http://localhost:3000',
  'https://yourdomain.com',
  'https://yourapp.vercel.app'
];
```

## 📊 Monitoring e Observability

### Prometheus Metrics

- **Edge Gateway**: `http://localhost:8787/metrics`
- **Core API**: `http://localhost:3000/metrics`
- **Model Router**: `http://localhost:3001/metrics`

### Grafana Dashboard

Accesso: `http://localhost:3000`
- Username: `admin`
- Password: `admin`

Dashboard disponibili:
- Request Rate
- Response Time
- Error Rate
- Cost per Request
- Model Usage

## 🧪 Testing

### Test di Carico

```bash
# Installa k6
curl -L https://github.com/grafana/k6/releases/latest/download/k6-linux-amd64.tar.gz | tar xz

# Esegui test
./k6 run load-test.js
```

### Test di Sicurezza

```bash
# Test rate limiting
for i in {1..110}; do
  curl -X POST http://localhost:8787/chat \
    -H "Content-Type: application/json" \
    -d '{"messages": [{"role": "user", "content": "test"}]}'
done

# Dovresti vedere errori 429 dopo 100 richieste
```

## 🔒 Sicurezza

### Best Practices Implementate

- **Rate Limiting**: 100 richieste/minuto per utente
- **JWT Authentication**: Validazione token per endpoint protetti
- **CORS**: Configurazione restrittiva per domini autorizzati
- **Input Validation**: Schema validation con Zod
- **SQL Injection Protection**: Prepared statements con pg
- **HTTPS Only**: Forzato in produzione

### Configurazione Sicurezza

```typescript
// Edge Gateway
app.use(helmet()); // Security headers
app.use(rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
}));
```

## 🚨 Troubleshooting

### Problemi Comuni

1. **Database Connection Failed**
   ```bash
   docker-compose logs postgres
   # Verifica che PostgreSQL sia in esecuzione
   ```

2. **Rate Limit Errors**
   - Verifica configurazione rate limiting
   - Controlla log per IP problematici

3. **Model API Errors**
   - Verifica API keys
   - Controlla quota OpenAI/Anthropic
   - Verifica circuit breaker status

4. **CORS Errors**
   - Verifica domini autorizzati
   - Controlla configurazione headers

### Log e Debug

```bash
# Visualizza log di tutti i servizi
docker-compose logs -f

# Log specifico servizio
docker-compose logs -f edge-gateway

# Log con timestamp
docker-compose logs -f --timestamps
```

## 📈 Scaling e Performance

### Ottimizzazioni Implementate

- **Connection Pooling**: Database connections riutilizzate
- **Caching**: Redis per rate limiting e cache
- **Streaming**: Server-Sent Events per latenza ridotta
- **Load Balancing**: Model router con fallback automatico
- **Circuit Breaker**: Protezione da failure cascade

### Metriche di Performance Target

- **Edge Gateway**: <100ms response time
- **Core API**: <500ms response time
- **Database**: <50ms query time
- **Uptime**: 99.99%

## 🔄 Aggiornamenti e Maintenance

### Update Process

1. **Pull latest changes**
   ```bash
   git pull origin main
   ```

2. **Rebuild e restart**
   ```bash
   docker-compose down
   docker-compose up -d --build
   ```

3. **Database migrations**
   ```bash
   docker-compose exec postgres psql -U ai_user -d ai_conversation -f migrations/new_migration.sql
   ```

### Backup e Recovery

```bash
# Backup database
docker-compose exec postgres pg_dump -U ai_user ai_conversation > backup.sql

# Restore database
docker-compose exec -T postgres psql -U ai_user -d ai_conversation < backup.sql
```

## 📞 Supporto

### Risorse Utili

- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Vercel Functions Docs](https://vercel.com/docs/functions)
- [PostgreSQL + pgvector](https://github.com/pgvector/pgvector)
- [Prometheus Documentation](https://prometheus.io/docs/)

### Contatti

Per supporto tecnico o domande:
- GitHub Issues: [Repository Issues](https://github.com/your-repo/issues)
- Email: support@yourdomain.com

---

**🎉 Congratulazioni!** Hai completato il deployment del sistema di conversazione AI enterprise. Il sistema è ora pronto per gestire conversazioni AI ad alta performance con fallback automatico, monitoring completo e sicurezza enterprise. 