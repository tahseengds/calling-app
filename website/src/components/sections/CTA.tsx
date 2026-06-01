'use client';

import { site } from '@/lib/site';
import { Reveal } from '@/components/ui/Reveal';
import { MagneticButton } from '@/components/ui/MagneticButton';

export function CTA() {
  return (
    <section id="download" className="relative overflow-hidden py-36 md:py-48">
      {/* Brand-blue ambient glow */}
      <div
        className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full"
        style={{
          width: 620,
          height: 620,
          background:
            'radial-gradient(circle, rgba(47,107,255,0.16) 0%, rgba(47,107,255,0.05) 50%, transparent 70%)',
          filter: 'blur(50px)',
        }}
      />

      <div className="relative z-10 mx-auto max-w-5xl px-6 text-center">
        <Reveal>
          <h2 className="mx-auto max-w-3xl text-balance font-display text-5xl font-semibold leading-[1.04] tracking-tight text-bone md:text-7xl">
            Bring everyone <span className="italic text-brand-300">closer</span>.
          </h2>
        </Reveal>

        <Reveal index={1}>
          <p className="mx-auto mt-6 max-w-md text-lg leading-relaxed text-bone/55">
            Free to start. Download {site.name} and make your first call in under a minute. No
            account required.
          </p>
        </Reveal>

        <Reveal index={2}>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
            <MagneticButton href={site.cta.primary.href}>
              <AppleGlyph /> App Store
            </MagneticButton>
            <MagneticButton href={site.cta.primary.href} variant="ghost">
              <PlayGlyph /> Google Play
            </MagneticButton>
          </div>
        </Reveal>

        <Reveal index={3}>
          <p className="mt-7 font-mono text-[11px] uppercase tracking-[0.14em] text-bone/30">
            iOS 15+ &nbsp;/&nbsp; Android 9+ &nbsp;/&nbsp; No ads &nbsp;/&nbsp; No tracking
          </p>
        </Reveal>
      </div>
    </section>
  );
}

function AppleGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M16.4 12.8c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.8-3.5.8-.7 0-1.8-.8-3-.8-1.5 0-2.9.9-3.7 2.3-1.6 2.7-.4 6.8 1.1 9 .7 1.1 1.6 2.3 2.7 2.3 1.1 0 1.5-.7 2.8-.7 1.3 0 1.6.7 2.8.7 1.2 0 1.9-1.1 2.6-2.2.8-1.2 1.2-2.4 1.2-2.5-.1 0-2.3-.9-2.4-3.6zM14.2 5.9c.6-.8 1-1.8.9-2.9-.9 0-2 .6-2.6 1.3-.6.7-1.1 1.7-.9 2.7 1 .1 2-.5 2.6-1.1z" />
    </svg>
  );
}

function PlayGlyph() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M4 3.2v17.6c0 .5.5.8.9.6l13.4-8.8c.4-.3.4-.9 0-1.2L4.9 2.6c-.4-.3-.9 0-.9.6z" />
    </svg>
  );
}
