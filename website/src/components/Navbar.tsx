'use client';

import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import clsx from 'clsx';
import { site } from '@/lib/site';
import { MagneticButton } from '@/components/ui/MagneticButton';

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <motion.header
      initial={{ y: -80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.9, delay: 1.8, ease: [0.16, 1, 0.3, 1] }}
      className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4"
    >
      <nav
        className={clsx(
          'flex w-full max-w-6xl items-center justify-between rounded-2xl px-5 py-3.5 transition-all duration-500',
          scrolled ? 'glass-strong shadow-card' : 'border border-transparent',
        )}
      >
        <a href="#top" className="flex items-center gap-2.5">
          <span className="h-6 w-6 rounded-lg bg-gradient-to-br from-brand-400 to-brand-glow shadow-glow-sm" />
          <span className="font-display text-[15px] font-bold tracking-tight text-white/90">
            {site.name}
          </span>
        </a>

        <ul className="hidden items-center gap-0.5 md:flex">
          {site.nav.map((item) => (
            <li key={item.href}>
              <a
                href={item.href}
                className="rounded-full px-4 py-2 text-sm text-white/55 transition-colors hover:text-white"
              >
                {item.label}
              </a>
            </li>
          ))}
        </ul>

        <MagneticButton href={site.cta.primary.href} className="px-5 py-2.5 text-[13px]">
          {site.cta.primary.label}
        </MagneticButton>
      </nav>
    </motion.header>
  );
}
