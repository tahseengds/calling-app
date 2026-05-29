'use client';

import { useRef, useState } from 'react';
import {
  AnimatePresence,
  motion,
  useMotionValueEvent,
  useScroll,
  useTransform,
} from 'framer-motion';
import { site } from '@/lib/site';
import { PhoneFrame, AppScreen } from '@/components/ui/PhoneMock';

const screens = ['chat', 'call', 'privacy'] as const;

/**
 * Cinematic scroll storytelling: the device is pinned (CSS sticky) while the
 * page scrolls, and the screen + copy crossfade through the story beats driven
 * by scroll progress.
 */
export function Experience() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start start', 'end end'],
  });

  const [active, setActive] = useState(0);
  useMotionValueEvent(scrollYProgress, 'change', (v) => {
    const i = Math.min(screens.length - 1, Math.floor(v * screens.length));
    setActive(i);
  });

  // Device parallax / subtle rotate across the whole section.
  const rotate = useTransform(scrollYProgress, [0, 1], [-6, 6]);
  const yDevice = useTransform(scrollYProgress, [0, 1], [40, -40]);

  return (
    <section id="experience" ref={ref} className="relative" style={{ height: '320vh' }}>
      <div className="sticky top-0 flex h-[100svh] items-center overflow-hidden">
        <div className="mx-auto grid w-full max-w-6xl grid-cols-1 items-center gap-12 px-6 md:grid-cols-2">
          {/* Copy */}
          <div className="order-2 md:order-1">
            <span className="rounded-full glass px-3.5 py-1.5 text-xs uppercase tracking-[0.2em] text-white/55">
              The experience
            </span>
            <div className="relative mt-6 h-[220px]">
              <AnimatePresence mode="wait">
                <motion.div
                  key={active}
                  initial={{ opacity: 0, y: 24, filter: 'blur(8px)' }}
                  animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
                  exit={{ opacity: 0, y: -24, filter: 'blur(8px)' }}
                  transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
                  className="absolute inset-0"
                >
                  <p className="text-sm font-medium text-brand-400">
                    {site.showcase[active].kicker}
                  </p>
                  <h3 className="mt-3 font-display text-4xl font-semibold leading-tight tracking-tightest md:text-5xl">
                    {site.showcase[active].title}
                  </h3>
                  <p className="mt-5 max-w-md text-lg leading-relaxed text-white/60">
                    {site.showcase[active].body}
                  </p>
                </motion.div>
              </AnimatePresence>

              {/* progress dots */}
              <div className="absolute -bottom-4 left-0 flex gap-2">
                {screens.map((_, i) => (
                  <span
                    key={i}
                    className={`h-1.5 rounded-full transition-all duration-500 ${
                      i === active ? 'w-8 bg-brand-400' : 'w-2 bg-white/20'
                    }`}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* Pinned device */}
          <div className="order-1 flex justify-center md:order-2">
            <motion.div style={{ rotate, y: yDevice }} className="will-change-transform">
              <PhoneFrame>
                <AnimatePresence mode="wait">
                  <motion.div
                    key={active}
                    className="absolute inset-0"
                    initial={{ opacity: 0, scale: 1.04 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.97 }}
                    transition={{ duration: 0.55, ease: [0.16, 1, 0.3, 1] }}
                  >
                    <AppScreen variant={screens[active]} />
                  </motion.div>
                </AnimatePresence>
              </PhoneFrame>
            </motion.div>
          </div>
        </div>
      </div>
    </section>
  );
}
