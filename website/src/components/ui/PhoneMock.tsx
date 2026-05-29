'use client';

import clsx from 'clsx';

/** Glass device frame. Children render as the "screen". */
export function PhoneFrame({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={clsx(
        'relative aspect-[9/19] w-[260px] rounded-[2.6rem] border border-white/12 bg-ink-900 p-2.5 shadow-card ring-glow',
        className,
      )}
    >
      <div className="relative h-full w-full overflow-hidden rounded-[2.1rem] bg-ink-950">
        {/* notch */}
        <div className="absolute left-1/2 top-2 z-20 h-5 w-20 -translate-x-1/2 rounded-full bg-black/80" />
        {children}
      </div>
    </div>
  );
}

const bubble = 'max-w-[78%] rounded-2xl px-3 py-2 text-[11px] leading-snug';

export function AppScreen({ variant }: { variant: 'chat' | 'call' | 'privacy' }) {
  if (variant === 'call') {
    return (
      <div className="flex h-full flex-col items-center justify-between bg-gradient-to-b from-brand-600/40 via-ink-900 to-ink-950 px-5 py-12">
        <div className="text-center">
          <div className="mx-auto mb-4 h-24 w-24 animate-float rounded-full bg-gradient-to-br from-brand-400 to-aqua shadow-glow" />
          <p className="text-sm font-medium">Grandma Rose</p>
          <p className="text-[11px] text-white/50">00:42 · HD video</p>
        </div>
        <div className="flex gap-3">
          {['mic', 'video', 'end'].map((b) => (
            <span
              key={b}
              className={clsx(
                'flex h-12 w-12 items-center justify-center rounded-full text-white',
                b === 'end' ? 'bg-red-500' : 'glass',
              )}
            >
              ●
            </span>
          ))}
        </div>
      </div>
    );
  }

  if (variant === 'privacy') {
    return (
      <div className="flex h-full flex-col gap-3 bg-gradient-to-b from-aqua/15 via-ink-900 to-ink-950 px-4 py-12">
        <p className="text-sm font-semibold">Privacy</p>
        {['End-to-end encryption', 'On-device intelligence', 'No ad tracking', 'App lock'].map(
          (t, i) => (
            <div
              key={t}
              className="flex items-center justify-between rounded-xl glass px-3 py-2.5 text-[11px]"
            >
              <span className="text-white/75">{t}</span>
              <span
                className={clsx(
                  'h-4 w-7 rounded-full p-0.5',
                  i === 2 ? 'bg-white/15' : 'bg-aqua/70',
                )}
              >
                <span
                  className={clsx(
                    'block h-3 w-3 rounded-full bg-white transition-transform',
                    i === 2 ? '' : 'translate-x-3',
                  )}
                />
              </span>
            </div>
          ),
        )}
      </div>
    );
  }

  // chat
  return (
    <div className="flex h-full flex-col bg-gradient-to-b from-brand-500/15 via-ink-900 to-ink-950 px-3 pb-3 pt-12">
      <p className="px-1 pb-2 text-[11px] font-semibold text-white/70">Family</p>
      <div className="flex flex-1 flex-col justify-end gap-2">
        <div className={clsx(bubble, 'self-start glass text-white/80')}>
          Landing in 20 — put the kettle on? ☕
        </div>
        <div className={clsx(bubble, 'self-end bg-brand-600 text-white')}>
          Already on. Drive safe! 💜
        </div>
        <div className={clsx(bubble, 'self-start glass text-white/80')}>📷 Photo</div>
        <div className="self-end text-5xl">😎</div>
      </div>
      <div className="mt-2 flex items-center gap-2 rounded-full glass px-3 py-2">
        <span className="text-[11px] text-white/40">Message…</span>
        <span className="ml-auto h-6 w-6 rounded-full bg-brand-500" />
      </div>
    </div>
  );
}
