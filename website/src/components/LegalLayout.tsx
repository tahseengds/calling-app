import Link from 'next/link';
import { Footer } from '@/components/sections/Footer';

export function LegalLayout({
  title,
  updated,
  intro,
  children,
}: {
  title: string;
  updated: string;
  intro: string;
  children: React.ReactNode;
}) {
  return (
    <>
      <article className="mx-auto max-w-3xl px-6 pb-24 pt-32 md:pt-40">
        <Link
          href="/"
          className="font-mono text-xs uppercase tracking-label text-brand-400/85 transition-colors hover:text-brand-300"
        >
          ← Back to home
        </Link>

        <h1 className="mt-8 font-display text-4xl font-semibold leading-[1.05] tracking-tight text-bone md:text-6xl">
          {title}
        </h1>
        <p className="mt-4 font-mono text-xs uppercase tracking-[0.12em] text-bone/35">
          Last updated {updated}
        </p>

        <p className="mt-8 text-lg leading-relaxed text-bone/60">{intro}</p>

        {/* Template notice — honest about what this is. */}
        <div className="mt-8 rounded-lg border border-brand-400/25 bg-brand-400/[0.06] px-5 py-4">
          <p className="text-sm leading-relaxed text-bone/70">
            This page is a starting template. Replace the placeholder clauses with your own
            terms and have them reviewed by legal counsel before launch.
          </p>
        </div>

        <div className="mt-12 space-y-10">{children}</div>
      </article>
      <Footer />
    </>
  );
}

export function LegalSection({
  heading,
  children,
}: {
  heading: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <h2 className="font-display text-2xl font-semibold tracking-tight text-bone md:text-3xl">
        {heading}
      </h2>
      <div className="mt-4 space-y-4 text-[15px] leading-relaxed text-bone/60">{children}</div>
    </section>
  );
}
