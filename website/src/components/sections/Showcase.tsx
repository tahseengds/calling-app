'use client';

import { useRef } from 'react';
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion';
import { SectionHeading } from '@/components/ui/SectionHeading';
import { PhoneFrame, AppScreen } from '@/components/ui/PhoneMock';
import { useIsMobile } from '@/hooks/useMediaQuery';

function FloatingCard({
  mx,
  my,
  depth,
  className,
  children,
}: {
  mx: ReturnType<typeof useSpring>;
  my: ReturnType<typeof useSpring>;
  depth: number;
  className?: string;
  children: React.ReactNode;
}) {
  const x = useTransform(mx, [-0.5, 0.5], [-depth, depth]);
  const y = useTransform(my, [-0.5, 0.5], [-depth, depth]);
  return (
    <motion.div
      style={{ x, y }}
      className={`surface-strong absolute hidden rounded-lg p-4 shadow-card md:block ${className ?? ''}`}
    >
      {children}
    </motion.div>
  );
}

export function Showcase() {
  const ref = useRef<HTMLDivElement>(null);
  const isMobile = useIsMobile();
  const mxRaw = useMotionValue(0);
  const myRaw = useMotionValue(0);
  const mx = useSpring(mxRaw, { stiffness: 80, damping: 18 });
  const my = useSpring(myRaw, { stiffness: 80, damping: 18 });
  const phoneRotateY = useTransform(mx, [-0.5, 0.5], [10, -10]);

  const onMove = (e: React.PointerEvent) => {
    if (isMobile || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    mxRaw.set((e.clientX - r.left) / r.width - 0.5);
    myRaw.set((e.clientY - r.top) / r.height - 0.5);
  };

  return (
    <section id="showcase" className="relative mx-auto max-w-6xl px-6 py-28 md:py-36">
      <SectionHeading
        title={
          <>
            Designed like a <span className="italic text-brand-300">flagship</span>
          </>
        }
        subtitle="Spatial, layered and tactile. Every surface answers to you."
      />

      <div
        ref={ref}
        onPointerMove={onMove}
        onPointerLeave={() => {
          mxRaw.set(0);
          myRaw.set(0);
        }}
        className="relative mx-auto mt-16 flex h-[560px] max-w-4xl items-center justify-center"
        style={{ perspective: 1200 }}
      >
        {/* glow */}
        <div className="pointer-events-none absolute h-[420px] w-[420px] rounded-full bg-brand-400/15 blur-[120px]" />

        <motion.div style={{ rotateY: phoneRotateY }}>
          <PhoneFrame>
            <AppScreen variant="call" />
          </PhoneFrame>
        </motion.div>

        <FloatingCard mx={mx} my={my} depth={50} className="left-2 top-12 w-52">
          <p className="text-xs text-bone/50">Incoming call</p>
          <p className="mt-1 text-sm font-medium text-bone">Dad · Video</p>
          <div className="mt-3 flex gap-2">
            <span className="h-8 flex-1 rounded-md bg-brand-400/70" />
            <span className="h-8 flex-1 rounded-md bg-red-500/80" />
          </div>
        </FloatingCard>

        <FloatingCard mx={mx} my={my} depth={70} className="right-0 top-28 w-44">
          <p className="text-xs text-bone/50">Reactions</p>
          <div className="mt-2 flex gap-1.5 text-xl">❤️ 😂 🔥 🎉</div>
        </FloatingCard>

        <FloatingCard mx={mx} my={my} depth={40} className="bottom-10 left-10 w-48">
          <p className="text-xs text-bone/50">Picture-in-picture</p>
          <div className="mt-2 h-16 w-24 rounded-md bg-gradient-to-br from-brand-300 to-brand-600" />
        </FloatingCard>

        <FloatingCard mx={mx} my={my} depth={60} className="bottom-16 right-6 w-40">
          <p className="text-xs text-bone/50">Call quality</p>
          <div className="mt-2 flex items-end gap-1">
            {[5, 9, 6, 11, 8, 12].map((h, i) => (
              <span key={i} className="w-2 rounded-sm bg-brand-400" style={{ height: h * 2 }} />
            ))}
          </div>
        </FloatingCard>
      </div>
    </section>
  );
}
