import { defineConfig } from 'astro/config';
import react from '@astrojs/react';

// This base path is required when publishing to shpalac.github.io/local-bluey/.
export default defineConfig({
  site: 'https://shpalac.github.io',
  base: '/local-bluey/',
  output: 'static',
  integrations: [react()],
});
