import type { VercelRequest, VercelResponse } from '@vercel/node';
import { Pool } from 'pg';

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// Health check function
async function checkDatabaseHealth() {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    return { status: 'healthy', latency: 'low' };
  } catch (error) {
    return { status: 'unhealthy', error: error instanceof Error ? error.message : 'Unknown error' };
  }
}

// Check environment variables
function checkEnvironment() {
  const required = ['OPENAI_API_KEY', 'DATABASE_URL'];
  const missing = required.filter(key => !process.env[key]);
  
  return {
    status: missing.length === 0 ? 'healthy' : 'unhealthy',
    missing_variables: missing.length > 0 ? missing : undefined
  };
}

// Main health check handler
export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  try {
    const startTime = Date.now();
    
    // Perform health checks
    const [dbHealth, envHealth] = await Promise.all([
      checkDatabaseHealth(),
      Promise.resolve(checkEnvironment())
    ]);
    
    const responseTime = Date.now() - startTime;
    
    // Determine overall health
    const overallStatus = dbHealth.status === 'healthy' && envHealth.status === 'healthy' 
      ? 'healthy' 
      : 'degraded';
    
    const response = {
      status: overallStatus,
      timestamp: new Date().toISOString(),
      service: 'ai-conversation-core',
      response_time_ms: responseTime,
      checks: {
        database: dbHealth,
        environment: envHealth
      },
      version: process.env.VERCEL_GIT_COMMIT_SHA || 'local',
      environment: process.env.NODE_ENV || 'development'
    };
    
    // Set appropriate status code
    const statusCode = overallStatus === 'healthy' ? 200 : 503;
    
    res.status(statusCode).json(response);
    
  } catch (error) {
    console.error('Health check error:', error);
    
    res.status(500).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      service: 'ai-conversation-core',
      error: 'Health check failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
} 