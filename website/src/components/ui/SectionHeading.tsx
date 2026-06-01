import { Reveal } from './Reveal';

export function SectionHeading({
  kicker,
  title,
  subtitle,
  align = 'left',
}: {
  kicker?: string;
  title: React.ReactNode;
  subtitle?: string;
  align?: 'center' | 'left';
}) {
  const alignment = align === 'center' ? 'text-center mx-auto items-center' : 'text-left items-start';
  return (
    <div className={`flex max-w-3xl flex-col ${alignment}`}>
      {kicker && (
        <Reveal>
          <span className="eyebrow">{kicker}</span>
        </Reveal>
      )}
      <Reveal index={kicker ? 1 : 0}>
        <h2 className="mt-5 font-display text-4xl font-semibold leading-[1.05] tracking-tight text-bone md:text-5xl lg:text-6xl">
          {title}
        </h2>
      </Reveal>
      {subtitle && (
        <Reveal index={2}>
          <p
            className={`mt-5 max-w-xl text-lg leading-relaxed text-bone/55 ${
              align === 'center' ? 'mx-auto' : ''
            }`}
          >
            {subtitle}
          </p>
        </Reveal>
      )}
    </div>
  );
}
