'use client';

import { useRef } from 'react';
import { motion } from 'framer-motion';
import { site } from '@/lib/site';
import { FeatureIcon } from '@/components/ui/Icons';

const ease = [0.16, 1, 0.3, 1] as const;

export function Features() {
  return (
    <section id="features" className="relative mx-auto max-w-6xl px-6 py-24 md:py-32">

      {/* Section label */}
      <motion.div
        className="mb-16 flex items-center gap-5"
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true }}
        transition={{ duration: 0.8 }}
      >
        <span className="h-px flex-1 bg-white/[0.07]" />
        <span className="text-[11px] uppercase tracking-[0.22em] text-white/35">
          What makes it different
        </span>
        <span className="h-px flex-1 bg-white/[0.07]" />
      </motion.div>

      {/* Feature list */}
      <div>
        {site.features.map((feature, i) => (
          <FeatureRow key={feature.title} feature={feature} index={i} />
        ))}
      </div>
    </section>
  );
}

function FeatureRow({
  feature,
  index,
}: {
  feature: (typeof site.features)[number];
  index: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-60px' }}
      transition={{ duration: 0.7, delay: index * 0.05, ease }}
      className="group relative"
    >
      {/* Top divider */}
      <div className="h-px bg-white/[0.07] transition-colors duration-500 group-hover:bg-white/[0.14]" />

      <div className="flex items-start gap-5 py-7 md:gap-8 md:py-8">
        {/* Number */}
        <span className="w-10 shrink-0 pt-0.5 font-display text-[11px] font-bold tracking-[0.15em] text-white/18">
          {String(index + 1).padStart(2, '0')}
        </span>

        {/* Icon */}
        <div
          className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl transition-all duration-300 group-hover:scale-110"
          style={{
            background: `${feature.accent}18`,
            border: `1px solid ${feature.accent}28`,
          }}
        >
          <FeatureIcon
            name={feature.icon}
            className="h-5 w-5 transition-colors"
            style={{ color: feature.accent }}
          />
        </div>

        {/* Text */}
        <div className="flex-1 min-w-0">
          <h3 className="font-display text-xl font-bold tracking-tight text-white/90 transition-colors group-hover:text-white md:text-2xl">
            {feature.title}
          </h3>
          <p className="mt-2 max-w-xl text-[15px] leading-relaxed text-white/40 transition-colors group-hover:text-white/55">
            {feature.body}
          </p>
        </div>

        {/* Arrow */}
        <span className="shrink-0 pt-1 text-lg text-white/15 transition-all duration-300 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-white/40">
          ↗
        </span>
      </div>

      {/* Left accent bar (on hover) */}
      <div
        className="absolute bottom-0 left-0 top-px w-0.5 scale-y-0 origin-top rounded-full transition-transform duration-500 group-hover:scale-y-100"
        style={{ background: feature.accent }}
      />
    </motion.div>
  );
}
