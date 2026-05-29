import { site } from '@/lib/site';
import { Reveal } from '@/components/ui/Reveal';

export function Stats() {
  return (
    <section className="relative mx-auto max-w-6xl px-6 py-16">
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-3xl glass md:grid-cols-4">
        {site.stats.map((s, i) => (
          <Reveal key={s.label} index={i} className="bg-white/[0.02] p-8 text-center">
            <div className="font-display text-4xl font-semibold tracking-tightest gradient-text-accent md:text-5xl">
              {s.value}
            </div>
            <div className="mt-2 text-sm text-white/50">{s.label}</div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
