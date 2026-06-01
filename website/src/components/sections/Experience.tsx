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

export function Experience() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start start', 'end end'],
  });

  const [active, setActive] = useState(0);
  useMotionValueEvent(scrollYProgress, 'change', (v) => {
    setActive(Math.min(screens.length - 1, Math.floor(v * screens.length)));
  });

  const yDevice = useTransform(scrollYProgress, [0, 1], [30, -30]);

  return (
    <section id="experience" ref={ref} className="relative" style={{ height: '300vh' }}>
      <div className="sticky top-0 flex h-[100svh] items-center overflow-hidden">
        <div className="mx-auto grid w-full max-w-6xl grid-cols-1 items-center gap-12 px-6 md:grid-cols-2">

          {/* Left — copy */}
          <div className="order-2 md:order-1">
            <div className="relative h-[260px]">
              <AnimatePresence mode="wait">
                <motion.div
                  key={active}
                  initial={{ opacity: 0, y: 28, filter: 'blur(8px)' }}
                  animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
                  exit={{ opacity: 0, y: -28, filter: 'blur(8px)' }}
                  transition={{ duration: 0.55, ease: [0.16, 1, 0.3, 1] }}
                  className="absolute inset-0"
                >
                  <span className="font-mono text-xs uppercase tracking-label text-brand-400/85">
                    {site.showcase[active].kicker}
                  </span>
                  <h3 className="mt-4 font-display text-4xl font-semibold leading-[1.05] tracking-tight text-bone md:text-5xl">
                    {site.showcase[active].title}
                  </h3>
                  <p className="mt-5 max-w-md text-lg leading-relaxed text-bone/55">
                    {site.showcase[active].body}
                  </p>
                </motion.div>
              </AnimatePresence>

              {/* Progress dots */}
              <div className="absolute -bottom-2 left-0 flex gap-2">
                {screens.map((_, i) => (
                  <span
                    key={i}
                    className={`h-1 rounded-full transition-all duration-500 ${
                      i === active ? 'w-8 bg-brand-400' : 'w-2 bg-bone/15'
                    }`}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* Right — device */}
          <div className="order-1 flex justify-center md:order-2">
            <motion.div
              style={{ y: yDevice }}
              className="will-change-transform"
              animate={{ y: [0, -10, 0] }}
              transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}
            >
              <div style={{ filter: 'drop-shadow(0 40px 60px rgba(47,107,255,0.20))' }}>
                <PhoneFrame>
                  <AnimatePresence mode="wait">
                    <motion.div
                      key={active}
                      className="absolute inset-0"
                      initial={{ opacity: 0, scale: 1.03 }}
                      animate={{ opacity: 1, scale: 1 }}
                      exit={{ opacity: 0, scale: 0.98 }}
                      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
                    >
                      <AppScreen variant={screens[active]} />
                    </motion.div>
                  </AnimatePresence>
                </PhoneFrame>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </section>
  );
}
