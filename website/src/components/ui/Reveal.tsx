'use client';

import { motion, type Variants } from 'framer-motion';
import type { ReactNode } from 'react';

const variants: Variants = {
  hidden: { opacity: 0, y: 28, filter: 'blur(6px)' },
  show: (i: number = 0) => ({
    opacity: 1,
    y: 0,
    filter: 'blur(0px)',
    transition: {
      duration: 0.8,
      delay: i * 0.08,
      ease: [0.16, 1, 0.3, 1], // expo-out
    },
  }),
};

type Props = {
  children: ReactNode;
  index?: number;
  className?: string;
  as?: 'div' | 'span' | 'li' | 'section';
};

/** Viewport-triggered fade/slide/blur reveal with stagger support. */
export function Reveal({ children, index = 0, className, as = 'div' }: Props) {
  const MotionTag = motion[as] as typeof motion.div;
  return (
    <MotionTag
      className={className}
      variants={variants}
      custom={index}
      initial="hidden"
      whileInView="show"
      viewport={{ once: true, margin: '-12% 0px' }}
    >
      {children}
    </MotionTag>
  );
}
