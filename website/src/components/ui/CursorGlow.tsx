'use client';

import { useEffect, useRef } from 'react';
import { useIsMobile } from '@/hooks/useMediaQuery';

/**
 * A soft brand-colored glow that lerps toward the cursor — the ambient
 * "spatial light" that follows you around the page. Pointer-events: none so it
 * never blocks interaction. Skipped on touch devices.
 */
export function CursorGlow() {
  const ref = useRef<HTMLDivElement>(null);
  const isMobile = useIsMobile();

  useEffect(() => {
    if (isMobile) return;
    const el = ref.current;
    if (!el) return;

    let raf = 0;
    const target = { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const pos = { ...target };

    const onMove = (e: PointerEvent) => {
      target.x = e.clientX;
      target.y = e.clientY;
    };
    window.addEventListener('pointermove', onMove);

    const loop = () => {
      pos.x += (target.x - pos.x) * 0.12;
      pos.y += (target.y - pos.y) * 0.12;
      el.style.transform = `translate3d(${pos.x - 250}px, ${pos.y - 250}px, 0)`;
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);

    return () => {
      window.removeEventListener('pointermove', onMove);
      cancelAnimationFrame(raf);
    };
  }, [isMobile]);

  if (isMobile) return null;

  return (
    <div
      ref={ref}
      aria-hidden
      className="pointer-events-none fixed left-0 top-0 z-[55] h-[500px] w-[500px] rounded-full opacity-60 mix-blend-screen blur-[80px] will-change-transform"
      style={{
        background:
          'radial-gradient(circle, rgba(124,92,255,0.35) 0%, rgba(70,224,208,0.12) 40%, transparent 70%)',
      }}
    />
  );
}
