'use client';

import { motion } from 'framer-motion';
import { site } from '@/lib/site';
import { FeatureIcon } from '@/components/ui/Icons';
import { Reveal } from '@/components/ui/Reveal';

const ease = [0.16, 1, 0.3, 1] as const;

export function Features() {
  return (
    <section id="features" className="relative mx-auto max-w-6xl px-6 py-24 md:py-32">
      {/* Editorial header — headline carries it, no eyebrow */}
      <div className="mb-14 max-w-2xl md:mb-20">
        <Reveal>
          <h2 className="font-display text-4xl font-semibold leading-[1.05] tracking-tight text-bone md:text-5xl lg:text-6xl">
            Everything a call <span className="italic text-brand-300">should be</span>.
          </h2>
        </Reveal>
        <Reveal index={1}>
          <p className="mt-5 max-w-lg text-lg leading-relaxed text-bone/55">
            Six things we got right, so the conversation is the only thing you notice.
          </p>
        </Reveal>
      </div>

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
      <div className="h-px bg-bone/[0.07] transition-colors duration-500 group-hover:bg-bone/[0.16]" />

      <div className="flex items-start gap-5 py-7 md:gap-8 md:py-8">
        {/* Number */}
        <span className="w-9 shrink-0 pt-1 font-mono text-[12px] tracking-[0.1em] text-brand-400/60 nums">
          {String(index + 1).padStart(2, '0')}
        </span>

        {/* Icon */}
        <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-brand-400/25 bg-brand-400/[0.08] transition-transform duration-300 group-hover:scale-110">
          <FeatureIcon name={feature.icon} className="h-5 w-5 text-brand-300" />
        </div>

        {/* Text */}
        <div className="min-w-0 flex-1">
          <h3 className="font-sans text-xl font-semibold tracking-tight text-bone/90 transition-colors group-hover:text-bone md:text-2xl">
            {feature.title}
          </h3>
          <p className="mt-2 max-w-xl text-[15px] leading-relaxed text-bone/45 transition-colors group-hover:text-bone/60">
            {feature.body}
          </p>
        </div>

        {/* Arrow */}
        <span className="shrink-0 pt-1 text-lg text-bone/15 transition-all duration-300 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-brand-400">
          ↗
        </span>
      </div>

      {/* Left accent bar (on hover) */}
      <div className="absolute bottom-0 left-0 top-px w-0.5 origin-top scale-y-0 rounded-full bg-brand-400 transition-transform duration-500 group-hover:scale-y-100" />
    </motion.div>
  );
}
