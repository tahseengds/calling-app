'use client';

import { useEffect, useRef } from 'react';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { site } from '@/lib/site';
import { SectionHeading } from '@/components/ui/SectionHeading';
import { GlassCard } from '@/components/ui/GlassCard';
import { FeatureIcon } from '@/components/ui/Icons';

export function Features() {
  const grid = useRef<HTMLDivElement>(null);

  // GSAP ScrollTrigger stagger reveal for the cards.
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const cards = grid.current?.querySelectorAll('[data-card]');
    if (!cards?.length) return;

    const ctx = gsap.context(() => {
      gsap.fromTo(
        cards,
        { y: 60, opacity: 0, filter: 'blur(8px)' },
        {
          y: 0,
          opacity: 1,
          filter: 'blur(0px)',
          duration: 0.9,
          ease: 'expo.out',
          stagger: 0.09,
          scrollTrigger: { trigger: grid.current, start: 'top 78%' },
        },
      );
    }, grid);

    return () => ctx.revert();
  }, []);

  return (
    <section id="features" className="relative mx-auto max-w-6xl px-6 py-28 md:py-36">
      <SectionHeading
        kicker="Built different"
        title={
          <>
            Everything you need to <span className="gradient-text-accent">stay close</span>
          </>
        }
        subtitle="A messaging and calling experience engineered to disappear into the moment — fast, private, and quietly beautiful."
      />

      <div
        ref={grid}
        className="mt-16 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3"
      >
        {site.features.map((f) => (
          <div data-card key={f.title}>
            <GlassCard accent={f.accent} className="h-full">
              <div
                className="mb-6 inline-flex h-12 w-12 items-center justify-center rounded-2xl"
                style={{
                  background: `linear-gradient(160deg, ${f.accent}33, transparent)`,
                  boxShadow: `inset 0 0 0 1px ${f.accent}44`,
                }}
              >
                <FeatureIcon name={f.icon} className="h-6 w-6" style={{ color: f.accent }} />
              </div>
              <h3 className="font-display text-xl font-semibold tracking-tight">{f.title}</h3>
              <p className="mt-3 text-[15px] leading-relaxed text-white/55">{f.body}</p>
            </GlassCard>
          </div>
        ))}
      </div>
    </section>
  );
}
