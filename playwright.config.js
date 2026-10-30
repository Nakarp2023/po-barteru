import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 30_000,
  retries: 1,
  reporter: 'list',
  use: {
    baseURL: process.env.BASE_URL || 'https://po-barteru-lightweight-nav-preview.onrender.com',
    headless: true,
    trace: 'retain-on-failure',
  },
});
