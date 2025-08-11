import type { VercelRequest, VercelResponse } from '@vercel/node';
import { z } from 'zod';
import { Pool } from 'pg';

// Request validation schema
const RAGQuerySchema = z.object({
  query: z.string().min(1),
  limit: z.number().min(1).max(20).default(5),
  similarity_threshold: z.number().min(0).max(1).default(0.7),
  include_metadata: z.boolean().default(true),
  search_type: z.enum(['hybrid', 'vector', 'text']).default('hybrid')
});

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// Vector similarity search using pgvector
async function vectorSearch(query: string, limit: number, threshold: number) {
  try {
    const client = await pool.connect();
    
    // Simple vector search (you'll need to implement proper embedding generation)
    const result = await client.query(`
      SELECT 
        id,
        content,
        metadata,
        embedding <-> $1 as distance
      FROM documents 
      WHERE embedding IS NOT NULL
      ORDER BY embedding <-> $1
      LIMIT $2
    `, [query, limit]);
    
    client.release();
    
    // Filter by similarity threshold
    return result.rows.filter(row => row.distance < threshold);
  } catch (error) {
    console.error('Vector search error:', error);
    return [];
  }
}

// Text-based search using PostgreSQL full-text search
async function textSearch(query: string, limit: number) {
  try {
    const client = await pool.connect();
    
    const result = await client.query(`
      SELECT 
        id,
        content,
        metadata,
        ts_rank(to_tsvector('english', content), plainto_tsquery('english', $1)) as rank
      FROM documents 
      WHERE to_tsvector('english', content) @@ plainto_tsquery('english', $1)
      ORDER BY rank DESC
      LIMIT $2
    `, [query, limit]);
    
    client.release();
    return result.rows;
  } catch (error) {
    console.error('Text search error:', error);
    return [];
  }
}

// Hybrid search combining vector and text search
async function hybridSearch(query: string, limit: number, threshold: number) {
  try {
    const [vectorResults, textResults] = await Promise.all([
      vectorSearch(query, Math.ceil(limit / 2), threshold),
      textSearch(query, Math.ceil(limit / 2))
    ]);
    
    // Combine and deduplicate results
    const combined = [...vectorResults, ...textResults];
    const unique = new Map();
    
    combined.forEach(result => {
      if (!unique.has(result.id)) {
        unique.set(result.id, {
          ...result,
          search_score: result.distance || result.rank || 0
        });
      }
    });
    
    // Sort by search score and return top results
    return Array.from(unique.values())
      .sort((a, b) => a.search_score - b.search_score)
      .slice(0, limit);
      
  } catch (error) {
    console.error('Hybrid search error:', error);
    return [];
  }
}

// Main RAG query handler
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
    const validatedBody = RAGQuerySchema.parse(req.body);
    const { query, limit, similarity_threshold, include_metadata, search_type } = validatedBody;
    
    let results;
    
    // Perform search based on type
    switch (search_type) {
      case 'vector':
        results = await vectorSearch(query, limit, similarity_threshold);
        break;
      case 'text':
        results = await textSearch(query, limit);
        break;
      case 'hybrid':
      default:
        results = await hybridSearch(query, limit, similarity_threshold);
        break;
    }
    
    // Format response
    const response = {
      query,
      results: results.map(result => ({
        id: result.id,
        content: result.content,
        ...(include_metadata && { metadata: result.metadata }),
        score: result.distance || result.rank || result.search_score || 0
      })),
      metadata: {
        total_results: results.length,
        search_type,
        similarity_threshold,
        query_length: query.length
      }
    };
    
    res.json(response);
    
  } catch (error) {
    console.error('RAG query error:', error);
    
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