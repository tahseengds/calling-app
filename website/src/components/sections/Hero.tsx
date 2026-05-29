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
  'Voice calls', 'Video calls', 'Group chats', 'E2E encrypted',
  'Picture-in-picture', 'Reactions', 'Voice messages', 'File sharing',
  'Read receipts', 'Smart notifications', 'Live presence', 'Sticker support',
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
        className="relative z-10 mx-auto flex w-full max-w-6xl flex-1 items-center px-6 pt-28 pb-20"
      >
        <div className="grid w-full grid-cols-1 items-center gap-16 md:grid-cols-[1fr_auto]">

          {/* Left — text */}
          <div className="max-w-xl">
            {/* Badge */}
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 1.8, ease }}
              className="mb-8 inline-flex items-center gap-2.5 rounded-full border border-white/10 bg-white/[0.04] px-4 py-1.5"
            >
              <span className="h-1.5 w-1.5 rounded-full bg-aqua animate-pulse-glow" />
              <span className="text-xs text-white/60">Now available · iOS & Android</span>
            </motion.div>

            {/* Headline */}
            <div className="overflow-hidden">
              <motion.span
                className="block font-display text-[64px] font-extrabold leading-[0.9] tracking-tightest text-white md:text-[80px] lg:text-[88px]"
                initial={{ y: 80, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ duration: 0.9, delay: 1.85, ease }}
              >
                Calls that
              </motion.span>
              <motion.span
                className="block font-display text-[64px] font-extrabold leading-[0.9] tracking-tightest text-white md:text-[80px] lg:text-[88px]"
                initial={{ y: 80, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ duration: 0.9, delay: 1.95, ease }}
              >
                feel like
              </motion.span>
              <motion.em
                className="not-italic block font-serif text-[66px] italic leading-[0.95] md:text-[82px] lg:text-[90px]"
                style={{
                  background: 'linear-gradient(110deg, #8b95ff 0%, #c8b4ff 50%, #46e0d0 100%)',
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                  backgroundClip: 'text',
                }}
                initial={{ y: 80, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                transition={{ duration: 0.9, delay: 2.05, ease }}
              >
                presence.
              </motion.em>
            </div>

            {/* Description */}
            <motion.p
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 2.3, ease }}
              className="mt-7 max-w-md text-lg leading-relaxed text-white/50"
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
              <MagneticButton href="#download">{site.cta.primary.label}</MagneticButton>
              <MagneticButton href="#experience" variant="ghost">
                ▶ {site.cta.secondary.label}
              </MagneticButton>
            </motion.div>

            {/* Trust chips */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 1, delay: 2.7 }}
              className="mt-8 flex flex-wrap gap-2"
            >
              {['E2E encrypted', '40ms calls', 'Zero data sold'].map((b) => (
                <span
                  key={b}
                  className="rounded-full border border-white/[0.08] px-3 py-1 text-xs text-white/40"
                >
                  {b}
                </span>
              ))}
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
                filter: 'drop-shadow(0 60px 80px rgba(109,124,255,0.28))',
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

      {/* Bottom marquee strip */}
      <div className="relative z-10 border-t border-white/[0.06] py-3.5 overflow-hidden">
        <div className="flex gap-0 whitespace-nowrap animate-marquee">
          {[...marqueeItems, ...marqueeItems].map((item, i) => (
            <span key={i} className="inline-flex items-center gap-5 px-5 text-sm text-white/25">
              {item}
              <span className="text-white/10">·</span>
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
