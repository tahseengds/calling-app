import { site } from '@/lib/site';

const groups = [
  { title: 'Product', links: ['Features', 'Experience', 'Showcase', 'Download'] },
  { title: 'Company', links: ['About', 'Careers', 'Press', 'Contact'] },
  { title: 'Legal', links: ['Privacy', 'Terms', 'Security', 'Status'] },
];

export function Footer() {
  return (
    <footer className="relative border-t border-white/10 px-6 py-16">
      <div className="mx-auto grid max-w-6xl grid-cols-2 gap-10 md:grid-cols-5">
        <div className="col-span-2">
          <div className="flex items-center gap-2.5">
            <span className="h-7 w-7 rounded-xl bg-gradient-to-br from-brand-400 to-brand-glow shadow-glow-sm" />
            <span className="font-display text-lg font-semibold tracking-tightest">
              {site.name}
            </span>
          </div>
          <p className="mt-4 max-w-xs text-sm leading-relaxed text-white/45">
            {site.tagline} Built for the people who matter most.
          </p>
        </div>

        {groups.map((g) => (
          <nav key={g.title} aria-label={g.title}>
            <h3 className="text-xs uppercase tracking-[0.2em] text-white/40">{g.title}</h3>
            <ul className="mt-4 space-y-2.5">
              {g.links.map((l) => (
                <li key={l}>
                  <a href="#" className="text-sm text-white/55 transition-colors hover:text-white">
                    {l}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>

      <div className="mx-auto mt-14 flex max-w-6xl flex-col items-center justify-between gap-4 border-t border-white/10 pt-8 text-xs text-white/35 md:flex-row">
        <p>© {new Date().getFullYear()} {site.name}. All rights reserved.</p>
        <p>Crafted with motion, light and care.</p>
      </div>
    </footer>
  );
}
