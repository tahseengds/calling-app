import { Reveal } from '@/components/ui/Reveal';
import { site } from '@/lib/site';

export function Stats() {
  return (
    <section className="relative mx-auto max-w-6xl px-6 py-20 md:py-28">
      <div className="divider mb-16 md:mb-20" />

      <div className="grid grid-cols-2 gap-y-14 gap-x-8 md:grid-cols-4">
        {site.stats.map((s, i) => (
          <Reveal key={s.label} index={i} className="flex flex-col items-center text-center">
            <div
              className="font-display text-5xl font-extrabold tracking-tightest md:text-6xl lg:text-7xl"
              style={{
                background: 'linear-gradient(110deg, #8b95ff 0%, #c8b4ff 50%, #46e0d0 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}
            >
              {s.value}
            </div>
            <div className="mt-3 text-[13px] text-white/35">{s.label}</div>
          </Reveal>
        ))}
      </div>

      <div className="divider mt-16 md:mt-20" />
    </section>
  );
}
