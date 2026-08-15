/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#080c14', surface: '#0f1420', surface2: '#161d2e', surface3: '#1e2740',
        border: '#222d44', border2: '#2a3a58',
        accent: '#4f8ef7', green: '#22c55e', amber: '#f59e0b',
        red: '#ef4444', purple: '#a855f7', cyan: '#06b6d4',
        txt: '#e8edf5', 'txt-dim': '#8a95a8', 'txt-muted': '#4e5a6e',
      },
      fontFamily: {
        display: ['Space Grotesk', 'sans-serif'],
        body: ['Inter', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
