# Lumio — Launch Website

An ultra-premium, fully animated, 3D launch site for the Lumio app. Built with
Next.js (App Router), React Three Fiber, GSAP, Framer Motion and Lenis smooth
scrolling — cinematic, immersive, and tuned for 60fps.

## Stack

- **Next.js 14** (App Router) + **TypeScript**
- **Tailwind CSS** (custom dark theme, glassmorphism, animated gradients)
- **Three.js / React Three Fiber / Drei** — procedural 3D phone + particle field
- **@react-three/postprocessing** — Bloom + Vignette
- **GSAP + ScrollTrigger** — scroll-linked stagger reveals
- **Framer Motion** — micro-interactions, scroll storytelling, transitions
- **Lenis** — eased smooth scrolling (synced to the GSAP ticker)

No binary assets are required — the 3D phone, its screen (a live GLSL shader),
particles, backgrounds and app mock-ups are all generated in code.

## Run locally

```bash
cd website
npm install        # or: pnpm install / yarn
npm run dev        # http://localhost:3000
```

```bash
npm run build      # production build
npm run start      # serve the production build
```

> Requires Node 18.18+.

## Architecture

```
src/
  app/                 # App Router: layout (SEO/fonts), page, robots, sitemap
  components/
    providers/         # Lenis ⇄ GSAP smooth-scroll provider
    three/             # R3F: HeroScene (Canvas), Phone (+GLSL), Particles
    sections/          # Hero, Features, Experience, Showcase, Stats, CTA, Footer
    ui/                # MagneticButton, GlassCard, CursorGlow, Reveal, PhoneMock…
  hooks/               # media-query / reduced-motion helpers
  lib/site.ts          # all copy + links (edit here, sections stay declarative)
```

## Performance & accessibility

- WebGL canvas is **lazily loaded** (`next/dynamic`, `ssr:false`) and only the
  hero uses it; every other section is CSS/Framer for a light GPU budget.
- **Mobile-adaptive**: lower DPR, fewer particles, bloom disabled on small/low-end.
- **`prefers-reduced-motion`** disables Lenis, floating and the heavy effects.
- Semantic HTML, metadata, Open Graph/Twitter, `robots`/`sitemap`, keyboard-
  friendly anchors.

## Customise

- Copy, stats, features, links → `src/lib/site.ts`
- Theme colors / animations → `tailwind.config.ts`
- Phone screen shader → `src/components/three/Phone.tsx`
- Replace `public/favicon.svg` and add an `opengraph-image.png` for richer cards.

## Deploy

Zero-config on any of:

- **Vercel** — import the repo, set the **Root Directory** to `website/`, deploy.
- **Netlify** — base directory `website/`, build `npm run build`, publish `.next`
  (with the Next.js plugin).
- **Cloudflare Pages** — framework preset **Next.js**, root `website/`.
