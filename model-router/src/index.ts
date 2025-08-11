import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { z } from 'zod';
import OpenAI from 'openai';
import Anthropic from '@anthropic-ai/sdk';
import winston from 'winston';

// Types
interface ModelConfig {
  name: string;
  provider: 'openai' | 'anthropic' | 'gpt-oss';
  model: string;
  maxTokens: number;
  costPer1kTokens: number;
  latency: number;
  quality: 'high' | 'medium' | 'low';
  region: 'global' | 'eu' | 'us';
  endpoint?: string; // Per GPT-OSS locale
}

interface RoutingDecision {
  model: ModelConfig;
  reason: string;
  estimatedCost: number;
  expectedLatency: number;
}

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});

// Model configurations - GPT-OSS è ora il DEFAULT
const models: ModelConfig[] = [
  // GPT-OSS models (nostri server locali) - PRIORITÀ ALTA
  {
    name: 'gpt-oss-20b',
    provider: 'gpt-oss',
    model: 'gpt-oss-20b',
    maxTokens: 8192,
    costPer1kTokens: 0.0001, // Costo ultra-basso (solo elettricità server)
    latency: 1000,
    quality: 'high',
    region: 'global',
    endpoint: process.env.GPT_OSS_20B_ENDPOINT || 'http://localhost:8000/v1'
  },
  {
    name: 'gpt-oss-120b',
    provider: 'gpt-oss',
    model: 'gpt-oss-120b',
    maxTokens: 8192,
    costPer1kTokens: 0.0002, // Costo ultra-basso (solo elettricità server)
    latency: 500,
    quality: 'high',
    region: 'global',
    endpoint: process.env.GPT_OSS_120B_ENDPOINT || 'http://localhost:8001/v1'
  },
  
  // OpenAI models (fallback) - PRIORITÀ MEDIA
  {
    name: 'gpt-4o',
    provider: 'openai',
    model: 'gpt-4o',
    maxTokens: 128000,
    costPer1kTokens: 0.005,
    latency: 2000,
    quality: 'high',
    region: 'global'
  },
  {
    name: 'gpt-4o-mini',
    provider: 'openai',
    model: 'gpt-4o-mini',
    maxTokens: 128000,
    costPer1kTokens: 0.00015,
    latency: 1500,
    quality: 'medium',
    region: 'global'
  },
  
  // Anthropic models (fallback) - PRIORITÀ BASSA
  {
    name: 'claude-3-5-sonnet',
    provider: 'anthropic',
    model: 'claude-3-5-sonnet-20241022',
    maxTokens: 200000,
    costPer1kTokens: 0.003,
    latency: 3000,
    quality: 'high',
    region: 'global'
  },
  {
    name: 'claude-3-haiku',
    provider: 'anthropic',
    model: 'claude-3-haiku-20240307',
    maxTokens: 200000,
    costPer1kTokens: 0.00025,
    latency: 1000,
    quality: 'medium',
    region: 'global'
  }
];

// AI Clients
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// GPT-OSS client per server locale
class GPTOSSClient {
  private endpoint: string;
  
  constructor(endpoint: string) {
    this.endpoint = endpoint;
  }
  
  async chatCompletion(messages: any[], options: any) {
    try {
      const response = await fetch(`${this.endpoint}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-oss-20b', // o gpt-oss-120b
          messages: messages.map(msg => ({
            role: msg.role,
            content: msg.content
          })),
          max_tokens: options.max_tokens || 1000,
          temperature: options.temperature || 0.7,
          stream: options.stream || false
        })
      });
      
      if (!response.ok) {
        throw new Error(`GPT-OSS API error: ${response.status}`);
      }
      
      return response.json();
    } catch (error) {
      logger.error('GPT-OSS API error:', error);
      throw error;
    }
  }
}

// Request validation schema
const ChatRequestSchema = z.object({
  messages: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string()
  })),
  quality: z.enum(['auto', 'max', 'cost_optimized']).default('auto'),
  max_tokens: z.number().optional(),
  eu_only: z.boolean().default(false),
  cost_cap: z.number().optional(),
  stream: z.boolean().default(false),
  prefer_local: z.boolean().default(true) // Nuovo: preferisci GPT-OSS locale
});

// Model selection logic - GPT-OSS è PRIORITARIO
function selectOptimalModel(
  request: z.infer<typeof ChatRequestSchema>,
  availableModels: ModelConfig[]
): RoutingDecision {
  const { quality, max_tokens, eu_only, cost_cap, prefer_local } = request;
  
  // Filter models based on requirements
  let candidates = availableModels.filter(model => {
    if (eu_only && model.region !== 'eu' && model.region !== 'global') return false;
    if (max_tokens && model.maxTokens < max_tokens) return false;
    return true;
  });
  
  if (candidates.length === 0) {
    throw new Error('No suitable models available');
  }
  
  // PRIORITÀ 1: Se prefer_local è true, GPT-OSS ha priorità massima
  if (prefer_local) {
    const gptOssModels = candidates.filter(m => m.provider === 'gpt-oss');
    if (gptOssModels.length > 0) {
      candidates = gptOssModels;
    }
  }
  
  // Calculate estimated costs
  const totalTokens = request.messages.reduce((sum, msg) => sum + msg.content.length / 4, 0);
  const estimatedOutputTokens = max_tokens || 1000;
  const totalEstimatedTokens = totalTokens + estimatedOutputTokens;
  
  // Score models - GPT-OSS ha bonus di priorità
  const scoredModels = candidates.map(model => {
    let score = 0;
    
    // Bonus per GPT-OSS (nostri server)
    if (model.provider === 'gpt-oss') {
      score += 1000; // Bonus massimo per modelli locali
    }
    
    // Quality scoring
    if (quality === 'max') {
      score += model.quality === 'high' ? 100 : model.quality === 'medium' ? 50 : 25;
    } else if (quality === 'cost_optimized') {
      score += (1 / model.costPer1kTokens) * 1000;
    } else {
      // Auto: balance quality and cost
      score += model.quality === 'high' ? 80 : model.quality === 'medium' ? 60 : 40;
      score += (1 / model.costPer1kTokens) * 500;
    }
    
    // Latency scoring
    score += (1 / model.latency) * 1000;
    
    // Cost cap compliance
    if (cost_cap) {
      const estimatedCost = (totalEstimatedTokens / 1000) * model.costPer1kTokens;
      if (estimatedCost > cost_cap) {
        score -= 1000; // Heavy penalty for exceeding cost cap
      }
    }
    
    return { model, score, estimatedCost: (totalEstimatedTokens / 1000) * model.costPer1kTokens };
  });
  
  // Sort by score and select best
  scoredModels.sort((a, b) => b.score - a.score);
  const selected = scoredModels[0];
  
  return {
    model: selected.model,
    reason: `Selected ${selected.model.name} (${selected.model.provider}) - ${selected.model.provider === 'gpt-oss' ? 'LOCAL SERVER' : 'EXTERNAL API'} - Quality: ${quality}, Cost: $${selected.estimatedCost.toFixed(4)}, Latency: ${selected.model.latency}ms`,
    estimatedCost: selected.estimatedCost,
    expectedLatency: selected.model.latency
  };
}

// Circuit breaker implementation
class CircuitBreaker {
  private failures = 0;
  private lastFailure = 0;
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';
  private readonly threshold = 3;
  private readonly timeout = 60000; // 1 minute
  
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailure > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }
    
    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  private onSuccess(): void {
    this.failures = 0;
    this.state = 'CLOSED';
  }
  
  private onFailure(): void {
    this.failures++;
    this.lastFailure = Date.now();
    
    if (this.failures >= this.threshold) {
      this.state = 'OPEN';
    }
  }
}

const circuitBreakers = new Map<string, CircuitBreaker>();

// Execute chat completion with fallback - GPT-OSS è PRIMO
async function executeWithFallback(
  request: z.infer<typeof ChatRequestSchema>,
  primaryModel: ModelConfig
): Promise<any> {
  // Ordina modelli per priorità: GPT-OSS prima, poi fallback
  const sortedModels = models.sort((a, b) => {
    if (a.provider === 'gpt-oss' && b.provider !== 'gpt-oss') return -1;
    if (b.provider === 'gpt-oss' && a.provider !== 'gpt-oss') return 1;
    return 0;
  });
  
  // Metti il modello primario all'inizio
  const executionOrder = [primaryModel, ...sortedModels.filter(m => m !== primaryModel)];
  
  for (const model of executionOrder) {
    const breakerKey = `${model.provider}:${model.model}`;
    let breaker = circuitBreakers.get(breakerKey);
    
    if (!breaker) {
      breaker = new CircuitBreaker();
      circuitBreakers.set(breakerKey, breaker);
    }
    
    try {
      const result = await breaker.execute(async () => {
        if (model.provider === 'gpt-oss') {
          // GPT-OSS locale
          const gptOssClient = new GPTOSSClient(model.endpoint!);
          return await gptOssClient.chatCompletion(request.messages, {
            max_tokens: request.max_tokens,
            stream: request.stream,
            temperature: 0.7
          });
        } else if (model.provider === 'openai') {
          // OpenAI
          return await openai.chat.completions.create({
            model: model.model,
            messages: request.messages,
            max_tokens: request.max_tokens,
            stream: request.stream,
            temperature: 0.7
          });
        } else {
          // Anthropic
          return await anthropic.messages.create({
            model: model.model,
            max_tokens: request.max_tokens || 1000,
            messages: request.messages.map(msg => ({
              role: msg.role === 'assistant' ? 'assistant' : msg.role,
              content: msg.content
            })),
            stream: request.stream
          });
        }
      });
      
      logger.info(`Successfully used model: ${model.name} (${model.provider})`, {
        model: model.name,
        provider: model.provider,
        cost: (request.messages.reduce((sum, msg) => sum + msg.content.length / 4, 0) / 1000) * model.costPer1kTokens,
        is_local: model.provider === 'gpt-oss'
      });
      
      return result;
      
    } catch (error) {
      logger.warn(`Model ${model.name} failed, trying next`, {
        model: model.name,
        provider: model.provider,
        error: error instanceof Error ? error.message : 'Unknown error'
      });
      
      if (model === executionOrder[executionOrder.length - 1]) {
        throw new Error('All models failed');
      }
    }
  }
}

// Express app setup
const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'ai-model-router',
    available_models: models.length,
    gpt_oss_models: models.filter(m => m.provider === 'gpt-oss').length,
    external_models: models.filter(m => m.provider !== 'gpt-oss').length,
    circuit_breakers: Array.from(circuitBreakers.entries()).map(([key, breaker]) => ({
      model: key,
      state: breaker['state']
    }))
  });
});

// Chat endpoint
app.post('/chat', async (req, res) => {
  try {
    // Validate request
    const validatedRequest = ChatRequestSchema.parse(req.body);
    
    // Select optimal model - GPT-OSS è PRIORITARIO
    const routingDecision = selectOptimalModel(validatedRequest, models);
    
    logger.info('Model routing decision', {
      selected_model: routingDecision.model.name,
      provider: routingDecision.model.provider,
      reason: routingDecision.reason,
      estimated_cost: routingDecision.estimatedCost,
      expected_latency: routingDecision.expectedLatency,
      is_local: routingDecision.model.provider === 'gpt-oss'
    });
    
    // Execute with fallback
    const result = await executeWithFallback(validatedRequest, routingDecision.model);
    
    // Add metadata to response
    const response = {
      ...result,
      metadata: {
        model_used: routingDecision.model.name,
        provider: routingDecision.model.provider,
        routing_reason: routingDecision.reason,
        estimated_cost: routingDecision.estimatedCost,
        expected_latency: routingDecision.expectedLatency,
        is_local_model: routingDecision.model.provider === 'gpt-oss',
        server_location: routingDecision.model.provider === 'gpt-oss' ? 'local' : 'external'
      }
    };
    
    res.json(response);
    
  } catch (error) {
    logger.error('Chat endpoint error', {
      error: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined
    });
    
    if (error instanceof z.ZodError) {
      return res.status(400).json({
        error: 'Validation error',
        details: error.errors
      });
    }
    
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// Start server
app.listen(PORT, () => {
  logger.info(`AI Model Router started on port ${PORT}`);
  logger.info(`Available models: ${models.map(m => m.name).join(', ')}`);
  logger.info(`GPT-OSS models: ${models.filter(m => m.provider === 'gpt-oss').map(m => m.name).join(', ')}`);
  logger.info(`External models: ${models.filter(m => m.provider !== 'gpt-oss').map(m => m.name).join(', ')}`);
}); 