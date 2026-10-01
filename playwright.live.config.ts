import { defineConfig } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import base from './playwright.config';
const env=parseEnv(readFileSync('.env.local','utf8'));
if(env.APP_ENV!=='development'||!env.SUPABASE_URL||!env.DEV_SUPABASE_PROJECT_REF||new URL(env.SUPABASE_URL).hostname!==`${env.DEV_SUPABASE_PROJECT_REF}.supabase.co`)throw new Error('Configura el proyecto Cloud DEV antes de pruebas live.');
export default defineConfig({...base,testDir:'./tests/live-browser',use:{...base.use,baseURL:'http://127.0.0.1:3101'},webServer:[{command:'node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3101',url:'http://127.0.0.1:3101/login',reuseExistingServer:false,timeout:120000,env:{...env,APP_URL:'http://127.0.0.1:3101',NEXT_TELEMETRY_DISABLED:'1'}}]});
