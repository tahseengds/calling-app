'use client';

import { useRef } from 'react';
import dynamic from 'next/dynamic';
import { motion, useMotionValue, useSpring, useScroll, useTransform } from 'framer-motion';
import { site } from '@/lib/site';
import { AuroraBackground } from '@/components/ui/AuroraBackground';
import { MagneticButton } from '@/components/ui/MagneticButton';
import { PhoneFrame, AppScreen } from '@/components/ui/PhoneMock';

const HeroScene = dynamic(() => import('@/components/three/HeroScene'), {
  ssr: false,
  loading: () => null,
});

const ease = [0.16, 1, 0.3, 1] as const;

const marqueeItems = [
  'Voice calls', 'Video calls', 'Group chats', 'End-to-end encrypted',
  'Picture-in-picture', 'Reactions', 'Voice messages', 'File sharing',
  'Read receipts', 'Smart notifications', 'Live presence', 'Stickers',
];

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] });
  const textY = useTransform(scrollYProgress, [0, 1], [0, 100]);
  const textOpacity = useTransform(scrollYProgress, [0, 0.6], [1, 0]);

  const mxRaw = useMotionValue(0);
  const myRaw = useMotionValue(0);
  const mx = useSpring(mxRaw, { stiffness: 60, damping: 20 });
  const my = useSpring(myRaw, { stiffness: 60, damping: 20 });

  const phoneRotateY = useTransform(mx, [-0.5, 0.5], [8, -8]);
  const phoneRotateX = useTransform(my, [-0.5, 0.5], [-5, 5]);

  const onPointerMove = (e: React.PointerEvent) => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    mxRaw.set((e.clientX - r.left) / r.width - 0.5);
    myRaw.set((e.clientY - r.top) / r.height - 0.5);
  };

  return (
    <section
      ref={ref}
      className="relative flex min-h-[100svh] flex-col overflow-hidden"
      onPointerMove={onPointerMove}
      onPointerLeave={() => { mxRaw.set(0); myRaw.set(0); }}
    >
      <AuroraBackground />
      <HeroScene />

      {/* Main content */}
      <motion.div
        style={{ y: textY, opacity: textOpacity }}
        className="relative z-10 mx-auto flex w-full max-w-6xl flex-1 items-center px-6 pt-24 pb-20"
      >
        <div className="grid w-full grid-cols-1 items-center gap-16 md:grid-cols-[1fr_auto]">

          {/* Left — text */}
          <div className="max-w-xl">
            {/* Eyebrow (the page's single hero label) */}
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 1.8, ease }}
              className="mb-8 inline-flex items-center gap-2.5 rounded-sm border border-bone/10 bg-ink-900/40 px-3.5 py-1.5"
            >
              <span className="h-1.5 w-1.5 rounded-full bg-brand-400 animate-pulse-glow" />
              <span className="font-mono text-[11px] uppercase tracking-label text-bone/55">
                Now on iOS &amp; Android
              </span>
            </motion.div>

            {/* Headline — editorial serif, two lines, same-family italic emphasis */}
            <h1 className="font-display text-bone">
              <div className="overflow-hidden">
                <motion.span
                  className="block text-[52px] font-semibold leading-[1.02] tracking-tight md:text-[68px] lg:text-[76px]"
                  initial={{ y: 80, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  transition={{ duration: 0.9, delay: 1.85, ease }}
                >
                  Calls that feel
                </motion.span>
              </div>
              <div className="overflow-hidden pb-2">
                <motion.span
                  className="block text-[52px] font-medium italic leading-[1.1] tracking-tight text-brand-300 md:text-[68px] lg:text-[76px]"
                  initial={{ y: 80, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  transition={{ duration: 0.9, delay: 1.98, ease }}
                >
                  like presence.
                </motion.span>
              </div>
            </h1>

            {/* Description */}
            <motion.p
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 2.3, ease }}
              className="mt-7 max-w-md text-lg leading-relaxed text-bone/55"
            >
              {site.description}
            </motion.p>

            {/* CTAs */}
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 2.45, ease }}
              className="mt-9 flex flex-wrap items-center gap-3"
            >
              <MagneticButton href={site.cta.primary.href}>{site.cta.primary.label}</MagneticButton>
              <MagneticButton href={site.cta.secondary.href} variant="ghost">
                {site.cta.secondary.label}
              </MagneticButton>
            </motion.div>
          </div>

          {/* Right — phone */}
          <motion.div
            className="hidden justify-center md:flex"
            initial={{ opacity: 0, y: 60 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 1.1, delay: 1.6, ease }}
          >
            <motion.div
              style={{
                filter: 'drop-shadow(0 60px 80px rgba(47,107,255,0.22))',
                rotateY: phoneRotateY,
                rotateX: phoneRotateX,
              }}
              animate={{ y: [0, -12, 0] }}
              transition={{ duration: 5, repeat: Infinity, ease: 'easeInOut' }}
              className="will-change-transform"
            >
              <PhoneFrame>
                <AppScreen variant="chat" />
              </PhoneFrame>
            </motion.div>
          </motion.div>
        </div>
      </motion.div>

      {/* Bottom capability strip (the page's single marquee) */}
      <div className="relative z-10 mask-fade-x overflow-hidden border-t border-bone/[0.07] py-3.5">
        <div className="flex gap-0 whitespace-nowrap animate-marquee">
          {[...marqueeItems, ...marqueeItems].map((item, i) => (
            <span
              key={i}
              className="inline-flex items-center gap-5 px-5 font-mono text-xs uppercase tracking-[0.15em] text-bone/30"
            >
              {item}
              <span className="text-brand-400/40">/</span>
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
