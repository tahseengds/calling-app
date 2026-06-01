'use client';

import { useRef } from 'react';
import { motion, useMotionValue, useSpring } from 'framer-motion';

export function MagneticButton({
  children,
  href,
  variant = 'solid',
  size = 'md',
}: {
  children: React.ReactNode;
  href: string;
  variant?: 'solid' | 'ghost';
  size?: 'sm' | 'md';
}) {
  const ref = useRef<HTMLAnchorElement>(null);
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const sx = useSpring(x, { stiffness: 200, damping: 15 });
  const sy = useSpring(y, { stiffness: 200, damping: 15 });

  // Continuous pointer value tracked outside the React render cycle.
  const onMove = (e: React.PointerEvent) => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    x.set((e.clientX - r.left - r.width / 2) * 0.25);
    y.set((e.clientY - r.top - r.height / 2) * 0.25);
  };
  const reset = () => {
    x.set(0);
    y.set(0);
  };

  // Editorial: squared, sharp. The single accent fills the primary CTA.
  const base =
    'group relative inline-flex items-center justify-center gap-2 rounded-sm font-sans font-medium ' +
    'transition-[background-color,border-color,color,transform] duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] ' +
    'active:scale-[0.98] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-400/70 focus-visible:ring-offset-2 focus-visible:ring-offset-ink-950';
  const sizes = { sm: 'px-5 py-2 text-sm', md: 'px-7 py-3.5 text-[15px]' };
  const variants = {
    // Brand blue with white label: high contrast, AA-safe on the accent.
    solid: 'bg-brand-500 text-white hover:bg-brand-400',
    ghost: 'border border-bone/20 text-bone hover:border-brand-400 hover:text-brand-300',
  };

  return (
    <motion.a
      ref={ref}
      href={href}
      style={{ x: sx, y: sy }}
      onPointerMove={onMove}
      onPointerLeave={reset}
      className={`${base} ${sizes[size]} ${variants[variant]}`}
    >
      {children}
    </motion.a>
  );
}
