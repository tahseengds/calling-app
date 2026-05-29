'use client';

import { useRef } from 'react';
import dynamic from 'next/dynamic';
import { motion, useScroll, useTransform } from 'framer-motion';
import { site } from '@/lib/site';
import { AuroraBackground } from '@/components/ui/AuroraBackground';
import { MagneticButton } from '@/components/ui/MagneticButton';

// WebGL is heavy + browser-only → load it lazily, never on the server.
const HeroScene = dynamic(() => import('@/components/three/HeroScene'), {
  ssr: false,
  loading: () => null,
});

const ease = [0.16, 1, 0.3, 1] as const;

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start start', 'end start'],
  });
  const y = useTransform(scrollYProgress, [0, 1], [0, 120]);
  const opacity = useTransform(scrollYProgress, [0, 0.7], [1, 0]);

  return (
    <section
      ref={ref}
      className="relative flex min-h-[100svh] items-center overflow-hidden pt-28"
    >
      <AuroraBackground />
      <HeroScene />

      <motion.div
        style={{ y, opacity }}
        className="relative z-10 mx-auto w-full max-w-6xl px-6"
      >
        <div className="max-w-2xl">
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 2.0, ease }}
            className="mb-6 inline-flex items-center gap-2 rounded-full glass px-4 py-1.5 text-xs text-white/70"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-aqua animate-pulse-glow" />
            New · Lumio 2.0 is here
          </motion.div>

          <h1 className="font-display text-balance text-5xl font-semibold leading-[0.98] tracking-tightest sm:text-6xl md:text-7xl">
            {['Calls that feel', 'like ', null].map((line, i) =>
              line === null ? (
                <span key={i} className="gradient-text-accent">
                  presence.
                </span>
              ) : (
                <motion.span
                  key={i}
                  className="block"
                  initial={{ opacity: 0, y: 28, filter: 'blur(8px)' }}
                  animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
                  transition={{ duration: 0.9, delay: 2.05 + i * 0.12, ease }}
                >
                  {line}
                </motion.span>
              ),
            )}
          </h1>

          <motion.p
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 2.4, ease }}
            className="mt-7 max-w-lg text-balance text-lg leading-relaxed text-white/65"
          >
            {site.description}
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 2.55, ease }}
            className="mt-9 flex flex-wrap items-center gap-3"
          >
            <MagneticButton href={site.cta.primary.href}>
              {site.cta.primary.label}
              <span aria-hidden>↓</span>
            </MagneticButton>
            <MagneticButton href={site.cta.secondary.href} variant="ghost">
              ▶ {site.cta.secondary.label}
            </MagneticButton>
          </motion.div>

          {/* Floating badges */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 1, delay: 2.8 }}
            className="mt-12 flex flex-wrap gap-3"
          >
            {['End-to-end encrypted', '4K video', 'iOS · Android'].map((b, i) => (
              <span
                key={b}
                className="rounded-full glass px-3.5 py-1.5 text-xs text-white/60 animate-float"
                style={{ animationDelay: `${i * 0.8}s` }}
              >
                {b}
              </span>
            ))}
          </motion.div>
        </div>
      </motion.div>

      {/* Scroll cue */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 3.1, duration: 1 }}
        className="absolute inset-x-0 bottom-8 z-10 flex justify-center"
      >
        <div className="flex h-9 w-5 items-start justify-center rounded-full border border-white/15 p-1">
          <span className="h-2 w-1 rounded-full bg-white/60 animate-float" />
        </div>
      </motion.div>
    </section>
  );
}
