import type { Config } from 'tailwindcss';

const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        ink: {
          950: '#06070f',
          900: '#0a0c18',
          800: '#101220',
          700: '#181a2e',
        },
        brand: {
          DEFAULT: '#6d7cff',
          400: '#8b95ff',
          500: '#6d7cff',
          600: '#5b6cf6',
          glow: '#7c5cff',
        },
        aqua: '#46e0d0',
        gold: '#d4a853',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        display: ['var(--font-display)', 'system-ui', 'sans-serif'],
        serif: ['var(--font-serif)', 'Georgia', 'serif'],
      },
      letterSpacing: {
        tightest: '-0.04em',
        tight: '-0.02em',
      },
      backdropBlur: {
        xs: '2px',
      },
      boxShadow: {
        glow: '0 0 60px -10px rgba(124, 92, 255, 0.55)',
        'glow-sm': '0 0 28px -8px rgba(124, 92, 255, 0.5)',
        card: '0 30px 80px -40px rgba(0, 0, 0, 0.8)',
        phone: '0 60px 120px -20px rgba(0,0,0,0.85), 0 0 0 1px rgba(0,0,0,0.7)',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        aurora: {
          '0%, 100%': { transform: 'translate(0, 0) scale(1)' },
          '33%': { transform: 'translate(4%, -6%) scale(1.08)' },
          '66%': { transform: 'translate(-5%, 4%) scale(0.96)' },
        },
        marquee: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        'pulse-glow': {
          '0%, 100%': { opacity: '0.4' },
          '50%': { opacity: '1' },
        },
        'ping-slow': {
          '0%': { transform: 'scale(1)', opacity: '0.6' },
          '100%': { transform: 'scale(1.6)', opacity: '0' },
        },
      },
      animation: {
        float: 'float 6s ease-in-out infinite',
        aurora: 'aurora 18s ease-in-out infinite',
        marquee: 'marquee 32s linear infinite',
        shimmer: 'shimmer 3.5s linear infinite',
        'pulse-glow': 'pulse-glow 3s ease-in-out infinite',
        'ping-slow': 'ping-slow 2s ease-out infinite',
      },
    },
  },
  plugins: [],
};

export default config;
