import { Reveal } from '@/components/ui/Reveal';
import { site } from '@/lib/site';

export function Stats() {
  return (
    <section className="relative mx-auto max-w-6xl px-6 py-20 md:py-28">
      <div className="divider mb-16 md:mb-20" />

      <div className="grid grid-cols-2 gap-y-14 gap-x-8 md:grid-cols-4">
        {site.stats.map((s, i) => (
          <Reveal key={s.label} index={i} className="flex flex-col items-center text-center">
            <div className="nums font-display text-5xl font-semibold tracking-tight text-brand-300 md:text-6xl lg:text-7xl">
              {s.value}
            </div>
            <div className="mt-3 font-mono text-[12px] uppercase tracking-[0.12em] text-bone/40">
              {s.label}
            </div>
          </Reveal>
        ))}
      </div>

      <div className="divider mt-16 md:mt-20" />
    </section>
  );
}
