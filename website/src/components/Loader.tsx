'use client';

import { useEffect, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';

/**
 * Intro overlay. Holds the brand reveal for a beat, runs a progress sweep,
 * then lifts away with a soft wipe. Locks scroll while visible.
 */
export function Loader() {
  const [done, setDone] = useState(false);

  useEffect(() => {
    const root = document.documentElement;
    root.style.overflow = 'hidden';
    const t = setTimeout(() => {
      setDone(true);
      root.style.overflow = '';
    }, 1700);
    return () => {
      clearTimeout(t);
      root.style.overflow = '';
    };
  }, []);

  return (
    <AnimatePresence>
      {!done && (
        <motion.div
          key="loader"
          className="fixed inset-0 z-[100] flex flex-col items-center justify-center bg-ink-950"
          initial={{ opacity: 1 }}
          exit={{ opacity: 0, filter: 'blur(12px)' }}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
        >
          <motion.div
            className="relative flex items-center gap-3"
            initial={{ opacity: 0, y: 14, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1] }}
          >
            <span className="relative flex h-11 w-11 items-center justify-center">
              <span className="absolute inset-0 rounded-2xl bg-gradient-to-br from-brand-300 to-brand-600 opacity-60 blur-md animate-pulse-glow" />
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/logo.png"
                alt="Lumio logo"
                width={44}
                height={44}
                className="relative h-11 w-11 rounded-2xl"
              />
            </span>
            <span className="font-display text-3xl font-semibold tracking-tight text-bone">
              Lumio
            </span>
          </motion.div>

          <div className="mt-8 h-px w-56 overflow-hidden bg-bone/10">
            <motion.div
              className="h-full bg-brand-400"
              initial={{ x: '-100%' }}
              animate={{ x: '0%' }}
              transition={{ duration: 1.4, ease: [0.16, 1, 0.3, 1] }}
            />
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
