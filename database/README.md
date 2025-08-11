# 🗄️ Database Setup - AI Conversation System

## 📋 Prerequisiti

- PostgreSQL 15+ installato e in esecuzione
- Estensione `pgvector` installata
- Estensione `uuid-ossp` disponibile

## �� Setup Locale (Sviluppo)

### 1. Avvia PostgreSQL
```bash
# macOS con Homebrew
brew services start postgresql

# Ubuntu/Debian
sudo systemctl start postgresql
```

### 2. Esegui lo script di setup
```bash
chmod +x setup-database.sh
./setup-database.sh
```

### 3. Verifica la connessione
```bash
psql -U postgres -d ai_conversation -c "SELECT version();"
```

## ☁️ Setup Supabase (Produzione)

### 1. Crea un progetto su Supabase
- Vai su [supabase.com](https://supabase.com)
- Crea un nuovo progetto
- Copia le credenziali

### 2. Configura le variabili d'ambiente
Copia `env.example` in `.env` e aggiorna:
```bash
cp env.example .env
# Modifica .env con le tue credenziali Supabase
```

### 3. Applica lo schema
```bash
# Usa la connection string di Supabase
psql "postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres" -f schema.sql
```

## 🔧 Estensioni Richieste

- `uuid-ossp`: Per generare UUID
- `pg_trgm`: Per ricerca full-text
- `vector`: Per embeddings e ricerca semantica

## 📊 Tabelle Create

- `documents`: Documenti per RAG
- `conversations`: Conversazioni utente
- `messages`: Messaggi nelle conversazioni
- `embeddings`: Cache embeddings
- `usage_tracking`: Tracciamento utilizzo
- `rate_limits`: Rate limiting

## 🔗 Connessione

**Locale:**
```
postgresql://postgres@localhost:5432/ai_conversation
```

**Supabase:**
```
postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres
```

## ✅ Verifica Setup

```bash
# Controlla le tabelle
psql -U postgres -d ai_conversation -c "\dt"

# Controlla le estensioni
psql -U postgres -d ai_conversation -c "\dx"
```
