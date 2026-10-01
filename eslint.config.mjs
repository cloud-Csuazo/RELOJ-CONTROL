import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';
import { fixupConfigRules } from '@eslint/compat';
export default defineConfig([...fixupConfigRules([...nextVitals, ...nextTs]), globalIgnores(['.next/**', 'node_modules/**', 'playwright-report/**', 'test-results/**', 'next-env.d.ts', 'work/**'])]);
