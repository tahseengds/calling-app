'use client';

import { useRef, type ReactNode } from 'react';
import { motion, useMotionTemplate, useMotionValue, useSpring } from 'framer-motion';
import clsx from 'clsx';
import { useIsMobile } from '@/hooks/useMediaQuery';

type Props = {
  children: ReactNode;
  className?: string;
  accent?: string;
};

/**
 * Glassmorphic card with 3D tilt toward the cursor and a spotlight that
 * tracks the pointer — depth-responsive, premium hover physics.
 */
export function GlassCard({ children, className, accent = '#6d7cff' }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const isMobile = useIsMobile();

  const rx = useSpring(useMotionValue(0), { stiffness: 150, damping: 18 });
  const ry = useSpring(useMotionValue(0), { stiffness: 150, damping: 18 });
  const mx = useMotionValue(50);
  const my = useMotionValue(50);
  const spotlight = useMotionTemplate`radial-gradient(420px circle at ${mx}% ${my}%, ${accent}22, transparent 45%)`;

  const onMove = (e: React.PointerEvent) => {
    if (isMobile || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width;
    const py = (e.clientY - r.top) / r.height;
    ry.set((px - 0.5) * 10);
    rx.set((0.5 - py) * 10);
    mx.set(px * 100);
    my.set(py * 100);
  };
  const onLeave = () => {
    rx.set(0);
    ry.set(0);
    mx.set(50);
    my.set(50);
  };

  return (
    <motion.div
      ref={ref}
      onPointerMove={onMove}
      onPointerLeave={onLeave}
      style={{ rotateX: rx, rotateY: ry, transformPerspective: 900 }}
      className={clsx(
        'group relative overflow-hidden rounded-3xl glass p-7 shadow-card will-change-transform',
        className,
      )}
    >
      <motion.div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-500 group-hover:opacity-100"
        style={{ background: spotlight }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -inset-px rounded-3xl opacity-0 transition-opacity duration-500 group-hover:opacity-100"
        style={{ boxShadow: `inset 0 0 0 1px ${accent}55` }}
      />
      <div className="relative z-10">{children}</div>
    </motion.div>
  );
}
