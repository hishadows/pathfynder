import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    open: '/admin.html', // dev server opens the admin page directly
  },
  build: {
    rollupOptions: {
      input: resolve(__dirname, 'admin.html'), // build entry = admin.html
    },
  },
})
