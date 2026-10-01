import { defineConfig, devices } from '@playwright/test';
import { existsSync } from 'node:fs';
const edge='C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
export default defineConfig({
  testDir:'./tests/e2e',testMatch:'*.spec.ts',fullyParallel:false,workers:1,retries:0,
  timeout:45000,expect:{timeout:12000},reporter:[['list'],['html',{open:'never'}]],
  use:{baseURL:'http://127.0.0.1:3100',trace:'retain-on-failure',screenshot:'only-on-failure',launchOptions:existsSync(edge)?{executablePath:edge}:{},...devices['Desktop Chrome']},
  webServer:[
    {command:'node node_modules/tsx/dist/cli.mjs tests/e2e/backend.ts',url:'http://127.0.0.1:55431/health',reuseExistingServer:false,timeout:120000},
    {command:'node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3100',url:'http://127.0.0.1:3100/login',reuseExistingServer:false,timeout:120000,env:{APP_ENV:'development',APP_URL:'http://127.0.0.1:3100',SUPABASE_URL:'http://127.0.0.1:55431',SUPABASE_PUBLISHABLE_KEY:'fixture-publishable-not-a-real-key',SUPABASE_SECRET_KEY:'fixture-service-only-not-a-real-key',RATE_LIMIT_HMAC_SECRET:'fixture-hmac-secret-at-least-thirty-two-chars',ENABLE_ACCESS_MANAGEMENT:'true',NEXT_TELEMETRY_DISABLED:'1'}}
  ]
});
