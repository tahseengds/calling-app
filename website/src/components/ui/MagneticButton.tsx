'use client';

import { useRef, type ReactNode } from 'react';
import { motion, useMotionValue, useSpring } from 'framer-motion';
import clsx from 'clsx';
import { useIsMobile } from '@/hooks/useMediaQuery';

type Props = {
  children: ReactNode;
  href?: string;
  onClick?: () => void;
  variant?: 'primary' | 'ghost';
  className?: string;
};

/** A button that magnetically leans toward the cursor with a glow on hover. */
export function MagneticButton({
  children,
  href,
  onClick,
  variant = 'primary',
  className,
}: Props) {
  const ref = useRef<HTMLAnchorElement>(null);
  const isMobile = useIsMobile();
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const sx = useSpring(x, { stiffness: 200, damping: 15 });
  const sy = useSpring(y, { stiffness: 200, damping: 15 });

  const handleMove = (e: React.PointerEvent) => {
    if (isMobile || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    x.set(((e.clientX - r.left) / r.width - 0.5) * 22);
    y.set(((e.clientY - r.top) / r.height - 0.5) * 22);
  };
  const reset = () => {
    x.set(0);
    y.set(0);
  };

  const base =
    'group relative inline-flex items-center justify-center gap-2 rounded-full px-7 py-3.5 text-sm font-medium tracking-tight transition-colors duration-300 will-change-transform';
  const styles =
    variant === 'primary'
      ? 'text-white ring-glow bg-gradient-to-b from-brand-500 to-brand-600 hover:from-brand-400 hover:to-brand-500'
      : 'text-white/90 glass hover:bg-white/[0.08]';

  return (
    <motion.a
      ref={ref}
      href={href}
      onClick={onClick}
      onPointerMove={handleMove}
      onPointerLeave={reset}
      style={{ x: sx, y: sy }}
      whileTap={{ scale: 0.96 }}
      className={clsx(base, styles, className)}
    >
      <span className="relative z-10 flex items-center gap-2">{children}</span>
      {variant === 'primary' && (
        <span
          aria-hidden
          className="absolute inset-0 rounded-full opacity-0 blur-md transition-opacity duration-300 group-hover:opacity-70"
          style={{ background: 'linear-gradient(180deg,#8b95ff,#7c5cff)' }}
        />
      )}
    </motion.a>
  );
}
