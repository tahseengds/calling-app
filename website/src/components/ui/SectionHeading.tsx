import { Reveal } from '@/components/ui/Reveal';

type Props = {
  kicker?: string;
  title: React.ReactNode;
  subtitle?: string;
  align?: 'center' | 'left';
};

export function SectionHeading({ kicker, title, subtitle, align = 'center' }: Props) {
  return (
    <div className={align === 'center' ? 'mx-auto max-w-2xl text-center' : 'max-w-2xl'}>
      {kicker && (
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full glass px-3.5 py-1.5 text-xs uppercase tracking-[0.2em] text-white/55">
            {kicker}
          </span>
        </Reveal>
      )}
      <Reveal index={1}>
        <h2 className="mt-5 font-display text-4xl font-semibold leading-tight tracking-tightest text-balance md:text-5xl">
          {title}
        </h2>
      </Reveal>
      {subtitle && (
        <Reveal index={2}>
          <p className="mt-4 text-balance text-lg leading-relaxed text-white/55">
            {subtitle}
          </p>
        </Reveal>
      )}
    </div>
  );
}
