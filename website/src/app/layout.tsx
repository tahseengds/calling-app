import type { Metadata, Viewport } from 'next';
import { Playfair_Display, DM_Sans, IBM_Plex_Mono } from 'next/font/google';
import './globals.css';
import { site } from '@/lib/site';
import { SmoothScroll } from '@/components/providers/SmoothScroll';
import { CursorGlow } from '@/components/ui/CursorGlow';
import { ScrollProgress } from '@/components/ui/ScrollProgress';
import { Navbar } from '@/components/Navbar';
import { Loader } from '@/components/Loader';

// Editorial display serif (justified: editorial direction; not the banned
// Instrument_Serif / Fraunces).
const playfair = Playfair_Display({
  subsets: ['latin'],
  weight: ['500', '600', '700', '800', '900'],
  style: ['normal', 'italic'],
  variable: '--font-display',
  display: 'swap',
});

const dmSans = DM_Sans({
  subsets: ['latin'],
  weight: ['300', '400', '500', '700'],
  variable: '--font-sans',
  display: 'swap',
});

// Mono for small labels / technical "encrypted" register.
const plexMono = IBM_Plex_Mono({
  subsets: ['latin'],
  weight: ['400', '500'],
  variable: '--font-mono',
  display: 'swap',
});

export const viewport: Viewport = {
  themeColor: '#08090c',
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
};

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.name} — ${site.tagline}`,
    template: `%s — ${site.name}`,
  },
  description: site.description,
  applicationName: site.name,
  keywords: ['Lumio', 'private messaging', 'video calling', 'voice calls', 'encrypted chat'],
  authors: [{ name: site.name }],
  openGraph: {
    type: 'website',
    url: site.url,
    title: `${site.name} — ${site.tagline}`,
    description: site.description,
    siteName: site.name,
  },
  twitter: {
    card: 'summary_large_image',
    title: `${site.name} — ${site.tagline}`,
    description: site.description,
  },
  robots: { index: true, follow: true },
  icons: {
    icon: [
      { url: '/logo.png', type: 'image/png' },
      { url: '/favicon.svg', type: 'image/svg+xml' },
    ],
    apple: '/logo.png',
    shortcut: '/logo.png',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="en"
      className={`${playfair.variable} ${dmSans.variable} ${plexMono.variable} dark`}
    >
      <body className="grain min-h-screen bg-ink-950 font-sans text-bone antialiased selection:bg-brand-400/30 selection:text-ink-950">
        <Loader />
        <SmoothScroll>
          <CursorGlow />
          <ScrollProgress />
          <Navbar />
          <main id="top">{children}</main>
        </SmoothScroll>
      </body>
    </html>
  );
}
