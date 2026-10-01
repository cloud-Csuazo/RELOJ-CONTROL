import 'server-only';
import { randomUUID } from 'node:crypto';
export function logEvent(event: string, level: 'info'|'warn'|'error' = 'info') {
  const requestId = randomUUID();
  // Intentionally excludes request bodies, email, passwords, tokens and provider errors.
  console[level](JSON.stringify({ event, requestId, timestamp: new Date().toISOString() }));
  return requestId;
}
