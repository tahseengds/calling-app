'use client';

import { useState } from 'react';
import { motion, useScroll, useMotionValueEvent } from 'framer-motion';
import { site } from '@/lib/site';
import { MagneticButton } from '@/components/ui/MagneticButton';

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const { scrollY } = useScroll();

  useMotionValueEvent(scrollY, 'change', (v) => setScrolled(v > 24));

  return (
    <motion.header
      initial={{ y: -100 }}
      animate={{ y: 0 }}
      transition={{ duration: 0.8, delay: 0.2, ease: [0.16, 1, 0.3, 1] }}
      className="fixed inset-x-0 top-0 z-50"
    >
      <div
        className={`transition-colors duration-500 ${
          scrolled
            ? 'border-b border-bone/[0.08] bg-ink-950/85 backdrop-blur-xl'
            : 'border-b border-transparent'
        }`}
      >
        <nav className="mx-auto flex h-16 max-w-7xl items-center justify-between px-6">
          {/* Wordmark */}
          <a href="#top" className="flex items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/logo.png"
              alt={`${site.name} logo`}
              width={30}
              height={30}
              className="h-[30px] w-[30px] rounded-lg shadow-glow-sm"
            />
            <span className="font-display text-lg font-semibold tracking-tight text-bone">
              {site.name}
            </span>
          </a>

          {/* Desktop nav */}
          <div className="hidden items-center gap-9 md:flex">
            {site.nav.map((item) => (
              <a
                key={item.label}
                href={item.href}
                className="group relative font-sans text-sm text-bone/55 transition-colors hover:text-bone"
              >
                {item.label}
                <span className="absolute -bottom-1.5 left-0 h-px w-0 bg-brand-400 transition-all duration-300 group-hover:w-full" />
              </a>
            ))}
          </div>

          {/* CTA */}
          <div className="hidden md:block">
            <MagneticButton href={site.cta.primary.href} size="sm">
              {site.cta.primary.label}
            </MagneticButton>
          </div>

          {/* Mobile toggle */}
          <button
            onClick={() => setOpen((o) => !o)}
            className="flex h-10 w-10 items-center justify-center rounded-sm border border-bone/12 md:hidden"
            aria-label="Menu"
            aria-expanded={open}
          >
            <div className="space-y-1.5">
              <span className={`block h-px w-5 bg-bone transition-all ${open ? 'translate-y-[6px] rotate-45' : ''}`} />
              <span className={`block h-px w-5 bg-bone transition-all ${open ? 'opacity-0' : ''}`} />
              <span className={`block h-px w-5 bg-bone transition-all ${open ? '-translate-y-[6px] -rotate-45' : ''}`} />
            </div>
          </button>
        </nav>
      </div>

      {/* Mobile menu */}
      <motion.div
        initial={false}
        animate={{ height: open ? 'auto' : 0, opacity: open ? 1 : 0 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="overflow-hidden md:hidden"
      >
        <div className="space-y-1 border-b border-bone/[0.08] bg-ink-950/95 px-6 py-5 backdrop-blur-xl">
          {site.nav.map((item) => (
            <a
              key={item.label}
              href={item.href}
              onClick={() => setOpen(false)}
              className="block py-2.5 text-sm text-bone/70 hover:text-bone"
            >
              {item.label}
            </a>
          ))}
          <div className="pt-3">
            <MagneticButton href={site.cta.primary.href} size="sm">
              {site.cta.primary.label}
            </MagneticButton>
          </div>
        </div>
      </motion.div>
    </motion.header>
  );
}
