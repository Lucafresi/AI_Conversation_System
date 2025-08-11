import type { VercelRequest, VercelResponse } from '@vercel/node';
import OpenAI from 'openai';
import Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { Pool } from 'pg';

// Request validation schema
const ChatRequestSchema = z.object({
  thread_id: z.string().optional(),
  messages: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
    metadata: z.record(z.any()).optional()
  })),
  tools_wanted: z.boolean().optional(),
  quality: z.enum(['auto', 'max', 'cost_optimized']).default('auto'),
  stream: z.boolean().default(true),
  model_preference: z.enum(['openai', 'anthropic', 'gpt-oss', 'auto']).optional(),
  prefer_local: z.boolean().default(true) // Nuovo: preferisci GPT-OSS locale
});

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// AI Clients
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// GPT-OSS client per server locale
class GPTOSSClient {
  private endpoint20b: string;
  private endpoint120b: string;
  
  constructor() {
    this.endpoint20b = process.env.GPT_OSS_20B_ENDPOINT || 'http://localhost:8000/v1';
    this.endpoint120b = process.env.GPT_OSS_120B_ENDPOINT || 'http://localhost:8001/v1';
  }
  
  async chatCompletion(messages: any[], options: any, model: 'gpt-oss-20b' | 'gpt-oss-120b') {
    try {
      const endpoint = model === 'gpt-oss-20b' ? this.endpoint20b : this.endpoint120b;
      
      const response = await fetch(`${endpoint}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: model,
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
      console.error('GPT-OSS API error:', error);
      throw error;
    }
  }
}

const gptOssClient = new GPTOSSClient();

// Model selection logic - GPT-OSS è PRIORITARIO
function selectModel(quality: string, contentLength: number, modelPreference?: string, preferLocal: boolean = true) {
  // Se c'è una preferenza specifica, rispettala
  if (modelPreference === 'openai') return 'openai';
  if (modelPreference === 'anthropic') return 'anthropic';
  if (modelPreference === 'gpt-oss') return 'gpt-oss-20b';
  
  // PRIORITÀ 1: Se prefer_local è true, GPT-OSS ha priorità massima
  if (preferLocal) {
    if (quality === 'max') {
      return 'gpt-oss-120b'; // Qualità massima con GPT-OSS locale
    } else if (quality === 'cost_optimized') {
      return 'gpt-oss-20b'; // Costo ultra-basso con GPT-OSS locale
    } else {
      return 'gpt-oss-20b'; // Default: GPT-OSS locale
    }
  }
  
  // Fallback a modelli esterni se GPT-OSS non preferito
  if (quality === 'max') {
    return contentLength > 10000 ? 'anthropic' : 'openai';
  }
  
  if (quality === 'cost_optimized') {
    return 'openai'; // GPT-4o-mini è più cost-effective
  }
  
  // Default: OpenAI per most cases
  return 'openai';
}

// RAG retrieval function
async function retrieveRelevantContext(query: string, limit: number = 5) {
  try {
    const client = await pool.connect();
    
    // Hybrid search: BM25 + vector similarity
    const result = await client.query(`
      SELECT 
        content,
        metadata,
        similarity(content, $1) as similarity_score
      FROM documents 
      WHERE content ILIKE $2
      ORDER BY similarity_score DESC, ts_rank(to_tsvector('english', content), plainto_tsquery('english', $1)) DESC
      LIMIT $3
    `, [query, `%${query}%`, limit]);
    
    client.release();
    return result.rows;
  } catch (error) {
    console.error('RAG retrieval error:', error);
    return [];
  }
}

// GPT-OSS chat completion
async function gptOssChatCompletion(messages: any[], stream: boolean, tools?: any[], model: 'gpt-oss-20b' | 'gpt-oss-120b') {
  const completion = await gptOssClient.chatCompletion(messages, {
    stream,
    max_tokens: 4000,
    temperature: 0.7
  }, model);
  
  return completion;
}

// OpenAI chat completion
async function openaiChatCompletion(messages: any[], stream: boolean, tools?: any[]) {
  const completion = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages,
    tools,
    stream,
    temperature: 0.7,
    max_tokens: 4000,
  });
  
  return completion;
}

// Anthropic chat completion
async function anthropicChatCompletion(messages: any[], stream: boolean, tools?: any[]) {
  // Convert OpenAI format to Anthropic format
  const anthropicMessages = messages.map(msg => ({
    role: msg.role === 'assistant' ? 'assistant' : msg.role,
    content: msg.content
  }));
  
  const completion = await anthropic.messages.create({
    model: 'claude-3-5-sonnet-20241022',
    max_tokens: 4000,
    messages: anthropicMessages,
    stream,
  });
  
  return completion;
}

// Main chat handler
export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  try {
    // Validate request
    const validatedBody = ChatRequestSchema.parse(req.body);
    const { messages, quality, stream, tools_wanted, model_preference, prefer_local } = validatedBody;
    
    // Get last user message for RAG
    const lastUserMessage = messages.filter(m => m.role === 'user').pop();
    let context = '';
    
    if (lastUserMessage && tools_wanted) {
      // Retrieve relevant context
      const relevantDocs = await retrieveRelevantContext(lastUserMessage.content);
      if (relevantDocs.length > 0) {
        context = `\n\nRelevant context:\n${relevantDocs.map(doc => doc.content).join('\n\n')}`;
      }
    }
    
    // Prepare messages with context
    const enhancedMessages = [...messages];
    if (context) {
      enhancedMessages.unshift({
        role: 'system',
        content: `You have access to the following relevant information: ${context}`
      });
    }
    
    // Select model - GPT-OSS è PRIORITARIO
    const selectedModel = selectModel(quality, JSON.stringify(enhancedMessages).length, model_preference, prefer_local);
    
    // Prepare tools if needed
    const tools = tools_wanted ? [
      {
        type: 'function',
        function: {
          name: 'search_documents',
          description: 'Search for relevant documents in the knowledge base',
          parameters: {
            type: 'object',
            properties: {
              query: {
                type: 'string',
                description: 'Search query'
              }
            },
            required: ['query']
          }
        }
      }
    ] : undefined;
    
    let completion;
    let modelProvider = 'unknown';
    
    // Execute with selected model - GPT-OSS è PRIMO
    if (selectedModel.startsWith('gpt-oss')) {
      completion = await gptOssChatCompletion(enhancedMessages, stream, tools, selectedModel as 'gpt-oss-20b' | 'gpt-oss-120b');
      modelProvider = 'gpt-oss';
    } else if (selectedModel === 'openai') {
      completion = await openaiChatCompletion(enhancedMessages, stream, tools);
      modelProvider = 'openai';
    } else {
      completion = await anthropicChatCompletion(enhancedMessages, stream, tools);
      modelProvider = 'anthropic';
    }
    
    if (stream) {
      // Handle streaming response
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      
      if (modelProvider === 'gpt-oss') {
        // GPT-OSS streaming (OpenAI-compatible format)
        for await (const chunk of completion) {
          const content = chunk.choices[0]?.delta?.content;
          if (content) {
            res.write(`data: ${JSON.stringify({ content, model: selectedModel, provider: 'gpt-oss' })}\n\n`);
          }
        }
      } else if (modelProvider === 'openai') {
        // OpenAI streaming
        for await (const chunk of completion) {
          const content = chunk.choices[0]?.delta?.content;
          if (content) {
            res.write(`data: ${JSON.stringify({ content, model: 'gpt-4o', provider: 'openai' })}\n\n`);
          }
        }
      } else {
        // Anthropic streaming
        for await (const chunk of completion) {
          if (chunk.type === 'content_block_delta') {
            res.write(`data: ${JSON.stringify({ content: chunk.delta.text, model: 'claude-3-5-sonnet', provider: 'anthropic' })}\n\n`);
          }
        }
      }
      
      res.write('data: [DONE]\n\n');
      res.end();
      
    } else {
      // Handle non-streaming response
      let content = '';
      let model = selectedModel;
      
      if (modelProvider === 'gpt-oss') {
        content = completion.choices[0]?.message?.content || '';
      } else if (modelProvider === 'openai') {
        content = completion.choices[0]?.message?.content || '';
      } else {
        content = completion.content[0]?.text || '';
      }
      
      res.json({
        content,
        model,
        thread_id: validatedBody.thread_id,
        metadata: {
          model_used: model,
          provider: modelProvider,
          quality,
          context_retrieved: context ? true : false,
          tokens_estimated: content.length / 4,
          is_local_model: modelProvider === 'gpt-oss',
          server_location: modelProvider === 'gpt-oss' ? 'local' : 'external'
        }
      });
    }
    
  } catch (error) {
    console.error('Chat API error:', error);
    
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
} 