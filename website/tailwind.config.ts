import type { Config } from 'tailwindcss';

/**
 * Design system — "Editorial, brand-blue"
 * Cool neutral near-black base, ONE accent: the logo's electric blue.
 * The accent is brand-derived (the Lumio mark is blue), so per the taste
 * skill's override it's embraced deliberately — single accent, neutral base,
 * restrained gradients. Legacy aliases (aqua/gold) repoint to brand so any
 * stray reference resolves to the single accent.
 */
const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        // Cool neutral near-black (faint blue tint, never warm).
        ink: {
          950: '#08090c',
          900: '#0c0d11',
          850: '#101116',
          800: '#15161d',
          700: '#1e2029',
          600: '#2b2e3a',
        },
        // The single accent — matched to the logo's electric blue.
        brand: {
          50: '#eaf1ff',
          100: '#d2e2ff',
          200: '#a9c6ff',
          300: '#7aa5ff',
          400: '#4f86fb',
          500: '#2f6bff',
          600: '#1f54e0',
          700: '#1a44b8',
          DEFAULT: '#2f6bff',
          glow: '#2f6bff',
        },
        // Cool off-white for text.
        bone: '#eef1f7',

        // --- Legacy aliases (repointed to brand; do not use in new code) ---
        aqua: '#7aa5ff',
        gold: '#4f86fb',
      },
      fontFamily: {
        // Editorial display serif (justified: editorial direction).
        display: ['var(--font-display)', 'Georgia', 'serif'],
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'SFMono-Regular', 'monospace'],
        serif: ['var(--font-display)', 'Georgia', 'serif'],
      },
      letterSpacing: {
        tightest: '-0.04em',
        tight: '-0.02em',
        label: '0.25em',
      },
      backdropBlur: {
        xs: '2px',
      },
      boxShadow: {
        // Blue-tinted glows (matched to the brand).
        glow: '0 0 60px -16px rgba(47, 107, 255, 0.42)',
        'glow-sm': '0 0 26px -8px rgba(47, 107, 255, 0.45)',
        card: '0 28px 70px -36px rgba(0, 0, 0, 0.85)',
        phone: '0 50px 110px -28px rgba(0,0,0,0.88), 0 0 0 1px rgba(0,0,0,0.7)',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        drift: {
          '0%, 100%': { transform: 'translate(0, 0) scale(1)' },
          '50%': { transform: 'translate(3%, -4%) scale(1.06)' },
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
          '0%, 100%': { opacity: '0.45' },
          '50%': { opacity: '1' },
        },
        'ping-slow': {
          '0%': { transform: 'scale(1)', opacity: '0.6' },
          '100%': { transform: 'scale(1.6)', opacity: '0' },
        },
        'load-bar': {
          '0%': { transform: 'scaleX(0)' },
          '100%': { transform: 'scaleX(1)' },
        },
      },
      animation: {
        float: 'float 6s ease-in-out infinite',
        drift: 'drift 22s ease-in-out infinite',
        marquee: 'marquee 40s linear infinite',
        shimmer: 'shimmer 3.5s linear infinite',
        'pulse-glow': 'pulse-glow 3s ease-in-out infinite',
        'ping-slow': 'ping-slow 2s ease-out infinite',
        'load-bar': 'load-bar 1.4s cubic-bezier(0.16,1,0.3,1) forwards',
      },
    },
  },
  plugins: [],
};

export default config;
