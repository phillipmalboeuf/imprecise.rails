import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  root: '.',
  server: {
    port: 3036,
    strictPort: true,
    origin: 'http://localhost:3036',
    hmr: {
      host: 'localhost',
      port: 3036,
    },
  },
  build: {
    outDir: 'app/assets/builds',
    emptyOutDir: true,
    manifest: true,
    rollupOptions: {
      input: 'app/javascript/application.tsx',
      output: {
        entryFileNames: 'application.js',
        assetFileNames: '[name].[ext]',
      },
    },
  },
  resolve: {
    alias: {
      '@': '/app/javascript',
    },
  },
})
