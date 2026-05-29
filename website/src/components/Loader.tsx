'use client';

import { useEffect, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';

/**
 * Cinematic intro overlay. Holds the brand reveal for a beat, runs a progress
 * sweep, then lifts away with a soft wipe. Locks scroll while visible.
 */
export function Loader() {
  const [done, setDone] = useState(false);

  useEffect(() => {
    const root = document.documentElement;
    root.style.overflow = 'hidden';
    const t = setTimeout(() => {
      setDone(true);
      root.style.overflow = '';
    }, 1900);
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
            <span className="relative flex h-10 w-10 items-center justify-center">
              <span className="absolute inset-0 rounded-2xl bg-gradient-to-br from-brand-400 to-brand-glow blur-md opacity-70 animate-pulse-glow" />
              <span className="relative h-10 w-10 rounded-2xl bg-gradient-to-br from-brand-400 to-brand-glow" />
            </span>
            <span className="font-display text-3xl font-semibold tracking-tightest text-white">
              Lumio
            </span>
          </motion.div>

          <div className="mt-8 h-px w-56 overflow-hidden bg-white/10">
            <motion.div
              className="h-full bg-gradient-to-r from-brand-400 to-aqua"
              initial={{ x: '-100%' }}
              animate={{ x: '0%' }}
              transition={{ duration: 1.6, ease: [0.16, 1, 0.3, 1] }}
            />
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
