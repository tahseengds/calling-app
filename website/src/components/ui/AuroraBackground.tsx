'use client';

import { motion } from 'framer-motion';

/**
 * Editorial cool ambience — one slow brand-blue glow over near-black, plus a faint
 * static wash. No colored mesh, no purple.
 */
export function AuroraBackground() {
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden">
      {/* base cool gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-ink-950 via-ink-900 to-ink-950" />

      {/* single drifting brand-blue light, kept low and slow */}
      <motion.div
        className="absolute -top-32 right-1/4 h-[520px] w-[520px] rounded-full"
        style={{
          background: 'radial-gradient(circle, rgba(47,107,255,0.16), transparent 70%)',
          filter: 'blur(90px)',
        }}
        animate={{ x: [0, 40, 0], y: [0, 30, 0] }}
        transition={{ duration: 22, repeat: Infinity, ease: 'easeInOut' }}
      />

      {/* faint static counter-wash for depth */}
      <div
        className="absolute bottom-0 left-1/4 h-[460px] w-[460px] rounded-full"
        style={{
          background: 'radial-gradient(circle, rgba(47,107,255,0.06), transparent 70%)',
          filter: 'blur(90px)',
        }}
      />

      {/* subtle vignette to seat the type */}
      <div
        className="absolute inset-0"
        style={{
          background:
            'radial-gradient(120% 90% at 50% 35%, transparent 55%, rgba(10,8,7,0.55) 100%)',
        }}
      />
    </div>
  );
}
