import { site } from '@/lib/site';

const links = [
  { label: 'Features', href: '#features' },
  { label: 'Experience', href: '#experience' },
  { label: 'Download', href: '#download' },
  { label: 'Privacy', href: '/privacy' },
  { label: 'Terms', href: '/terms' },
];

export function Footer() {
  return (
    <footer className="relative border-t border-bone/[0.07] px-6 py-12">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-8 md:flex-row md:items-center">
        {/* Brand */}
        <div>
          <div className="flex items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/logo.png"
              alt={`${site.name} logo`}
              width={28}
              height={28}
              className="h-7 w-7 rounded-lg shadow-glow-sm"
            />
            <span className="font-display text-base font-semibold tracking-tight text-bone">
              {site.name}
            </span>
          </div>
          <p className="mt-2 text-sm text-bone/40">{site.tagline}</p>
        </div>

        {/* Nav */}
        <nav className="flex flex-wrap gap-x-7 gap-y-2">
          {links.map((l) => (
            <a
              key={l.label}
              href={l.href}
              className="text-sm text-bone/45 transition-colors hover:text-bone"
            >
              {l.label}
            </a>
          ))}
        </nav>
      </div>

      <div className="mx-auto mt-10 flex max-w-6xl flex-col gap-2 border-t border-bone/[0.05] pt-6 text-xs text-bone/25 sm:flex-row sm:items-center sm:justify-between">
        <p>© {new Date().getFullYear()} {site.name}. All rights reserved.</p>
        <p className="font-mono uppercase tracking-[0.14em]">End-to-end encrypted</p>
      </div>
    </footer>
  );
}
