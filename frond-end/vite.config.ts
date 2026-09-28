import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': new URL('./src', import.meta.url).pathname },
  },
  server: {
    port: 5174,
    proxy: {
      // Dev proxy so the dashboard talks to Laravel without CORS setup.
      '/api': { target: 'http://127.0.0.1:8000', changeOrigin: true },
      // Uploaded media (menu photos, logos) live on Laravel's public disk.
      '/storage': { target: 'http://127.0.0.1:8000', changeOrigin: true },
    },
  },
})
