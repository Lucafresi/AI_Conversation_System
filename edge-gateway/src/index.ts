import { Router } from 'itty-router';
import { z } from 'zod';

// Types
interface Env {
  AI_CONFIG: KVNamespace;
  AI_CACHE: R2Bucket;
  CORE_API_URL: string;
  JWT_SECRET: string;
}

// Request validation schemas
const ChatRequestSchema = z.object({
  thread_id: z.string().optional(),
  messages: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
    metadata: z.record(z.any()).optional()
  })),
  tools_wanted: z.boolean().optional(),
  quality: z.enum(['auto', 'max', 'cost_optimized']).default('auto'),
  stream: z.boolean().default(true)
});

const AuthHeaderSchema = z.object({
  authorization: z.string().regex(/^Bearer .+/)
});

// Router setup
const router = Router();

// Middleware: CORS
const corsMiddleware = (request: Request) => {
  const origin = request.headers.get('Origin');
  const allowedOrigins = ['http://localhost:3000', 'https://yourdomain.com'];
  
  if (origin && allowedOrigins.includes(origin)) {
    return new Response(null, {
      status: 200,
      headers: {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '86400',
      },
    });
  }
  
  return new Response(null, {
    status: 200,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
};

// Middleware: Rate Limiting
const rateLimitMiddleware = async (request: Request, env: Env) => {
  const clientId = request.headers.get('X-Client-ID') || 'anonymous';
  const key = `rate_limit:${clientId}`;
  
  try {
    const current = await env.AI_CONFIG.get(key);
    const limit = 100; // requests per minute
    const window = 60; // seconds
    
    if (current) {
      const [count, timestamp] = current.split(':').map(Number);
      if (Date.now() - timestamp < window * 1000) {
        if (count >= limit) {
          return new Response('Rate limit exceeded', { status: 429 });
        }
        await env.AI_CONFIG.put(key, `${count + 1}:${timestamp}`);
      } else {
        await env.AI_CONFIG.put(key, `1:${Date.now()}`);
      }
    } else {
      await env.AI_CONFIG.put(key, `1:${Date.now()}`);
    }
  } catch (error) {
    console.error('Rate limiting error:', error);
  }
};

// Middleware: Authentication
const authMiddleware = async (request: Request, env: Env) => {
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) {
      return new Response('Unauthorized', { status: 401 });
    }
    
    // Simple JWT validation (in production, use proper JWT library)
    const token = authHeader.replace('Bearer ', '');
    
    // For now, accept any token (you'll implement proper JWT validation)
    // In production: verify JWT signature, check expiration, etc.
    
    return null; // Continue to next middleware
  } catch (error) {
    return new Response('Invalid token', { status: 401 });
  }
};

// Health check endpoint
router.get('/health', () => {
  return new Response(JSON.stringify({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'ai-conversation-edge'
  }), {
    headers: { 'Content-Type': 'application/json' }
  });
});

// Chat endpoint
router.post('/chat', async (request: Request, env: Env) => {
  try {
    // Parse and validate request
    const body = await request.json();
    const validatedBody = ChatRequestSchema.parse(body);
    
    // Check cache first
    const cacheKey = `chat:${JSON.stringify(validatedBody)}`;
    const cached = await env.AI_CACHE.get(cacheKey);
    
    if (cached && validatedBody.quality !== 'max') {
      return new Response(cached.body, {
        headers: {
          'Content-Type': 'application/json',
          'X-Cache': 'HIT',
          'X-Cache-Key': cacheKey
        }
      });
    }
    
    // Forward to Core API
    const coreResponse = await fetch(`${env.CORE_API_URL}/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': request.headers.get('Authorization') || '',
        'X-Edge-Request': 'true'
      },
      body: JSON.stringify(validatedBody)
    });
    
    if (!coreResponse.ok) {
      throw new Error(`Core API error: ${coreResponse.status}`);
    }
    
    // Handle streaming response
    if (validatedBody.stream && coreResponse.headers.get('content-type')?.includes('text/event-stream')) {
      const stream = new ReadableStream({
        async start(controller) {
          const reader = coreResponse.body?.getReader();
          if (!reader) return;
          
          try {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              
              controller.enqueue(value);
            }
          } finally {
            reader.releaseLock();
            controller.close();
          }
        }
      });
      
      return new Response(stream, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        }
      });
    }
    
    // Handle non-streaming response
    const response = await coreResponse.json();
    
    // Cache the response (for non-max quality requests)
    if (validatedBody.quality !== 'max') {
      await env.AI_CACHE.put(cacheKey, JSON.stringify(response), {
        expirationTtl: 300 // 5 minutes
      });
    }
    
    return new Response(JSON.stringify(response), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('Chat endpoint error:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});

// RAG query endpoint
router.post('/rag/query', async (request: Request, env: Env) => {
  try {
    const body = await request.json();
    
    const coreResponse = await fetch(`${env.CORE_API_URL}/rag/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': request.headers.get('Authorization') || ''
      },
      body: JSON.stringify(body)
    });
    
    if (!coreResponse.ok) {
      throw new Error(`Core API error: ${coreResponse.status}`);
    }
    
    const response = await coreResponse.json();
    return new Response(JSON.stringify(response), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('RAG query error:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});

// Default handler
router.all('*', () => new Response('Not Found', { status: 404 }));

// Main handler
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return corsMiddleware(request);
    }
    
    // Apply CORS headers
    const corsResponse = corsMiddleware(request);
    if (corsResponse) return corsResponse;
    
    try {
      // Apply rate limiting
      const rateLimitResponse = await rateLimitMiddleware(request, env);
      if (rateLimitResponse) return rateLimitResponse;
      
      // Apply authentication for protected routes
      if (request.url.includes('/chat') || request.url.includes('/rag')) {
        const authResponse = await authMiddleware(request, env);
        if (authResponse) return authResponse;
      }
      
      // Route the request
      return router.handle(request, env, ctx) || new Response('Not Found', { status: 404 });
      
    } catch (error) {
      console.error('Edge Gateway error:', error);
      return new Response(JSON.stringify({
        error: 'Internal server error',
        message: 'An unexpected error occurred'
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
}; 