'use client';

import clsx from 'clsx';

export function PhoneFrame({
  children,
  className,
  tilt = true,
}: {
  children: React.ReactNode;
  className?: string;
  tilt?: boolean;
}) {
  return (
    <div
      className={clsx('relative shrink-0', className)}
      style={{ width: 272, height: 554 }}
    >
      {/* Outer metallic shell */}
      <div
        className="absolute inset-0 rounded-[52px]"
        style={{
          background: 'linear-gradient(160deg, #252535 0%, #17172a 45%, #0e0e1c 100%)',
          boxShadow: `
            inset 0 1.5px 0 rgba(255,255,255,0.13),
            inset 0 -1.5px 0 rgba(0,0,0,0.55),
            inset 1.5px 0 0 rgba(255,255,255,0.06),
            inset -1.5px 0 0 rgba(0,0,0,0.35),
            0 0 0 1px rgba(0,0,0,0.75),
            0 50px 100px -20px rgba(0,0,0,0.85),
            0 10px 40px -10px rgba(0,0,0,0.5),
            0 0 80px -30px rgba(109,124,255,0.3)
          `,
        }}
      />

      {/* Left side: mute switch */}
      <div
        className="absolute rounded-l-sm"
        style={{
          left: -4,
          top: 80,
          width: 4,
          height: 20,
          background: 'linear-gradient(to right, #141424, #1e1e32)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.07), 0 1px 0 rgba(0,0,0,0.4)',
        }}
      />
      {/* Left side: vol+ */}
      <div
        className="absolute rounded-l-sm"
        style={{
          left: -4,
          top: 116,
          width: 4,
          height: 34,
          background: 'linear-gradient(to right, #141424, #1e1e32)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.07), 0 1px 0 rgba(0,0,0,0.4)',
        }}
      />
      {/* Left side: vol− */}
      <div
        className="absolute rounded-l-sm"
        style={{
          left: -4,
          top: 162,
          width: 4,
          height: 34,
          background: 'linear-gradient(to right, #141424, #1e1e32)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.07), 0 1px 0 rgba(0,0,0,0.4)',
        }}
      />
      {/* Right side: power button */}
      <div
        className="absolute rounded-r-sm"
        style={{
          right: -4,
          top: 130,
          width: 4,
          height: 52,
          background: 'linear-gradient(to left, #141424, #1e1e32)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.07), 0 1px 0 rgba(0,0,0,0.4)',
        }}
      />

      {/* Screen area */}
      <div
        className="absolute overflow-hidden bg-black"
        style={{
          inset: 10,
          borderRadius: 44,
        }}
      >
        {/* Dynamic Island */}
        <div
          className="absolute left-1/2 z-30 -translate-x-1/2"
          style={{
            top: 12,
            width: 112,
            height: 32,
            borderRadius: 999,
            background: '#000',
            boxShadow: '0 0 0 1px rgba(255,255,255,0.04)',
          }}
        />

        {/* Status bar */}
        <div
          className="absolute inset-x-0 top-0 z-20 flex items-center justify-between"
          style={{ padding: '16px 24px 0' }}
        >
          <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.92)', lineHeight: 1, letterSpacing: '-0.01em' }}>
            9:41
          </span>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            {/* Signal bars */}
            <svg width="15" height="11" viewBox="0 0 15 11" fill="rgba(255,255,255,0.88)">
              <rect x="0" y="8" width="2.5" height="3" rx="0.6" />
              <rect x="4" y="5.5" width="2.5" height="5.5" rx="0.6" />
              <rect x="8" y="3" width="2.5" height="8" rx="0.6" />
              <rect x="12" y="0" width="2.5" height="11" rx="0.6" />
            </svg>
            {/* WiFi */}
            <svg width="14" height="11" viewBox="0 0 14 11" fill="rgba(255,255,255,0.88)">
              <path d="M7 8.5a1.1 1.1 0 1 1 0 2.2A1.1 1.1 0 0 1 7 8.5z" />
              <path d="M7 5.8c1.3 0 2.5.5 3.4 1.4l-1.1 1.1a3 3 0 0 0-4.6 0L3.6 7.2A5 5 0 0 1 7 5.8z" opacity=".6" />
              <path d="M7 3c2 0 3.8.8 5.1 2.1l-1.1 1.1A6 6 0 0 0 1 5.1L-.1 4A8 8 0 0 1 7 3z" opacity=".35" />
            </svg>
            {/* Battery */}
            <svg width="21" height="11" viewBox="0 0 21 11" fill="none">
              <rect x="0.5" y="0.5" width="16.5" height="10" rx="3.5" stroke="rgba(255,255,255,0.45)" strokeWidth="1" />
              <rect x="1.5" y="1.5" width="13.5" height="8" rx="2.5" fill="rgba(255,255,255,0.9)" />
              <path d="M18 3.5v4a1.5 1.5 0 0 0 0-4z" fill="rgba(255,255,255,0.45)" />
            </svg>
          </div>
        </div>

        {/* Content */}
        <div className="absolute inset-0" style={{ paddingTop: 52, paddingBottom: 24 }}>
          {children}
        </div>

        {/* Home indicator */}
        <div className="absolute inset-x-0 bottom-2 z-20 flex justify-center">
          <div
            style={{
              width: 100,
              height: 4,
              borderRadius: 999,
              background: 'rgba(255,255,255,0.28)',
            }}
          />
        </div>

        {/* Screen glare */}
        <div
          className="pointer-events-none absolute inset-0 z-10"
          style={{
            background: 'linear-gradient(155deg, rgba(255,255,255,0.045) 0%, transparent 40%)',
          }}
        />
      </div>
    </div>
  );
}

export function AppScreen({ variant }: { variant: 'chat' | 'call' | 'privacy' }) {
  if (variant === 'call') {
    return (
      <div
        className="relative flex h-full flex-col items-center justify-between px-5 pb-4 pt-2"
        style={{ background: 'linear-gradient(180deg, #1c0b4a 0%, #0e0528 55%, #060310 100%)' }}
      >
        {/* Top bar */}
        <div className="flex w-full items-center justify-between">
          <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.35)' }}>swipe to minimize</span>
          <div
            style={{
              background: 'rgba(70,224,208,0.12)',
              border: '1px solid rgba(70,224,208,0.3)',
              borderRadius: 999,
              padding: '2px 8px',
            }}
          >
            <span style={{ fontSize: 9, color: '#46e0d0' }}>HD · E2E</span>
          </div>
        </div>

        {/* Avatar + info */}
        <div className="flex flex-col items-center gap-4">
          <div className="relative flex items-center justify-center">
            <div
              className="absolute rounded-full"
              style={{
                inset: -16,
                background: 'rgba(109,124,255,0.12)',
                animation: 'ping-slow 2s ease-out infinite',
              }}
            />
            <div
              className="absolute rounded-full"
              style={{
                inset: -8,
                background: 'rgba(109,124,255,0.18)',
                animation: 'ping-slow 2s ease-out 0.5s infinite',
              }}
            />
            <div
              style={{
                width: 90,
                height: 90,
                borderRadius: '50%',
                background: 'linear-gradient(135deg, #9c93ff 0%, #6d7cff 50%, #46e0d0 100%)',
                boxShadow: '0 0 40px rgba(109,124,255,0.5), 0 0 80px rgba(109,124,255,0.2)',
              }}
            />
          </div>
          <div className="text-center">
            <p style={{ fontSize: 15, fontWeight: 600, color: '#fff' }}>Grandma Rose</p>
            <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.45)', marginTop: 2 }}>Video call · 03:42</p>
          </div>
        </div>

        {/* Call controls */}
        <div className="flex items-center gap-3">
          {[
            { label: 'M', emoji: '🎙', bg: 'rgba(255,255,255,0.1)' },
            { label: 'V', emoji: '📹', bg: 'rgba(255,255,255,0.1)' },
            { label: 'E', emoji: '☎', bg: '#ef4444', size: 56 },
            { label: 'S', emoji: '🔊', bg: 'rgba(255,255,255,0.1)' },
          ].map((b) => (
            <div
              key={b.label}
              style={{
                width: b.size ?? 44,
                height: b.size ?? 44,
                borderRadius: '50%',
                background: b.bg,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: b.size ? 20 : 16,
              }}
            >
              {b.emoji}
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (variant === 'privacy') {
    return (
      <div
        className="flex h-full flex-col gap-1.5 px-3 py-2"
        style={{ background: 'linear-gradient(180deg, #080f1e 0%, #050912 100%)' }}
      >
        <p style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255,255,255,0.9)', padding: '0 4px 6px' }}>
          Privacy
        </p>
        {[
          { label: 'End-to-end encryption', on: true },
          { label: 'On-device processing', on: true },
          { label: 'No ad tracking', on: true },
          { label: 'Screen lock', on: false },
          { label: 'Read receipts', on: true },
          { label: 'Typing indicators', on: true },
        ].map(({ label, on }) => (
          <div
            key={label}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: 'rgba(255,255,255,0.03)',
              border: '1px solid rgba(255,255,255,0.06)',
              borderRadius: 12,
              padding: '8px 10px',
            }}
          >
            <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.75)' }}>{label}</span>
            <div
              style={{
                width: 30,
                height: 17,
                borderRadius: 999,
                background: on ? '#6d7cff' : 'rgba(255,255,255,0.08)',
                padding: '2.5px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: on ? 'flex-end' : 'flex-start',
                transition: 'background 0.2s',
              }}
            >
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#fff' }} />
            </div>
          </div>
        ))}
      </div>
    );
  }

  // chat
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: 'linear-gradient(180deg, #0c0c1c 0%, #07070f 100%)' }}
    >
      {/* Chat header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '8px 12px',
          borderBottom: '1px solid rgba(255,255,255,0.05)',
        }}
      >
        <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', marginRight: 2 }}>←</span>
        <div
          style={{
            width: 30,
            height: 30,
            borderRadius: '50%',
            background: 'linear-gradient(135deg, #ff9ad5, #c8b4ff)',
            flexShrink: 0,
          }}
        />
        <div style={{ minWidth: 0, flex: 1 }}>
          <p style={{ fontSize: 11, fontWeight: 600, color: '#fff', lineHeight: 1.2 }}>Sofia</p>
          <p style={{ fontSize: 9, color: '#4ade80', lineHeight: 1.2 }}>online</p>
        </div>
        <div style={{ display: 'flex', gap: 10, fontSize: 15 }}>
          <span>📞</span>
          <span>🎥</span>
        </div>
      </div>

      {/* Messages */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'flex-end',
          gap: 8,
          padding: '8px 12px',
          overflow: 'hidden',
        }}
      >
        {/* received */}
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6 }}>
          <div
            style={{
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: 'linear-gradient(135deg, #ff9ad5, #c8b4ff)',
              flexShrink: 0,
            }}
          />
          <div>
            <div
              style={{
                display: 'inline-block',
                background: 'rgba(255,255,255,0.08)',
                borderRadius: '14px 14px 14px 4px',
                padding: '7px 10px',
                maxWidth: 150,
              }}
            >
              <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.88)', lineHeight: 1.4 }}>
                Landing at 7 — kettle on? ☕
              </p>
            </div>
          </div>
        </div>

        {/* sent */}
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <div>
            <div
              style={{
                display: 'inline-block',
                background: '#6d7cff',
                borderRadius: '14px 14px 4px 14px',
                padding: '7px 10px',
                maxWidth: 150,
              }}
            >
              <p style={{ fontSize: 10, color: '#fff', lineHeight: 1.4 }}>
                Already on! Drive safe 💜
              </p>
            </div>
            <p style={{ textAlign: 'right', fontSize: 8, color: 'rgba(255,255,255,0.3)', marginTop: 2 }}>✓✓</p>
          </div>
        </div>

        {/* received emoji + reaction */}
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6 }}>
          <div
            style={{
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: 'linear-gradient(135deg, #ff9ad5, #c8b4ff)',
              flexShrink: 0,
            }}
          />
          <div>
            <div
              style={{
                display: 'inline-block',
                background: 'rgba(255,255,255,0.06)',
                borderRadius: '14px 14px 14px 4px',
                padding: '6px 8px',
              }}
            >
              <span style={{ fontSize: 20 }}>😎</span>
            </div>
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 3,
                background: 'rgba(255,255,255,0.06)',
                border: '1px solid rgba(255,255,255,0.08)',
                borderRadius: 999,
                padding: '2px 6px',
                marginTop: 3,
              }}
            >
              <span style={{ fontSize: 9 }}>❤️ 2</span>
            </div>
          </div>
        </div>

        {/* sent photo */}
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <div
            style={{
              width: 88,
              height: 66,
              borderRadius: 12,
              background: 'linear-gradient(135deg, #8b95ff, #46e0d0)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              overflow: 'hidden',
            }}
          >
            <span style={{ fontSize: 24 }}>🌅</span>
          </div>
        </div>
      </div>

      {/* Input bar */}
      <div style={{ padding: '6px 10px 6px' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            background: 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.07)',
            borderRadius: 999,
            padding: '7px 10px',
          }}
        >
          <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', flex: 1 }}>Message Sofia…</span>
          <span style={{ fontSize: 13 }}>🎙</span>
          <div
            style={{
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: '#6d7cff',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 10,
              color: '#fff',
            }}
          >
            ↑
          </div>
        </div>
      </div>
    </div>
  );
}
