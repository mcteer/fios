// Test-only parent process used to verify that stdin EOF reaps its private worker.
import { AgentClient } from '../../src/agent/client.js';
const client = new AgentClient();
await client.ready();
process.stdout.write(JSON.stringify({pid:client.pid})+'\n');
setInterval(()=>{},1000);
