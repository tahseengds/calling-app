/** Single source of truth for copy + links, so sections stay declarative. */
export const site = {
  name: 'Lumio',
  tagline: 'Calls that feel like presence.',
  description:
    'Lumio is a private chat, voice and video app — end-to-end fast, beautifully simple, and built for the people who matter most.',
  url: 'https://lumio.app',
  cta: {
    primary: { label: 'Get the app', href: '#download' },
    secondary: { label: 'Watch the film', href: '#showcase' },
  },
  nav: [
    { label: 'Features', href: '#features' },
    { label: 'Experience', href: '#experience' },
    { label: 'Showcase', href: '#showcase' },
    { label: 'Download', href: '#download' },
  ],
  stats: [
    { value: '40ms', label: 'median call setup' },
    { value: '4K', label: 'adaptive video' },
    { value: '0', label: 'data sold, ever' },
    { value: '99.99%', label: 'call uptime' },
  ],
  features: [
    {
      title: 'Crystal voice & video',
      body: 'Adaptive 4K video and studio-grade audio that hold up on a train, a tunnel, or a coffee shop.',
      icon: 'video',
      accent: '#6d7cff',
    },
    {
      title: 'Private by design',
      body: 'End-to-end encrypted messages and calls. Your conversations never leave your circle.',
      icon: 'shield',
      accent: '#46e0d0',
    },
    {
      title: 'Instant, everywhere',
      body: 'Calls connect in a blink and follow you across phone, tablet and desktop without a beat dropped.',
      icon: 'bolt',
      accent: '#c8b4ff',
    },
    {
      title: 'Expressive messaging',
      body: 'Reactions, stickers, voice notes and jumbo emoji — say it the way it actually feels.',
      icon: 'spark',
      accent: '#ff9ad5',
    },
    {
      title: 'Picture-in-picture',
      body: 'Float a call into a corner and keep doing everything else. Presence without the friction.',
      icon: 'layers',
      accent: '#ffd479',
    },
    {
      title: 'Effortless groups',
      body: 'Family, friends, teams — bring everyone in with a tap. No links, no logins, no friction.',
      icon: 'people',
      accent: '#7c5cff',
    },
  ],
  showcase: [
    {
      kicker: 'Conversations',
      title: 'A space that breathes',
      body: 'Threads that feel alive — typing presence, read state, reactions and media that load the instant you need them.',
    },
    {
      kicker: 'Calling',
      title: 'Be there, instantly',
      body: 'One tap to voice or video. Glassy controls, real-time quality, and a ringtone that actually rings.',
    },
    {
      kicker: 'You, in control',
      title: 'Yours, end to end',
      body: 'Granular privacy, on-device intelligence, and zero ad tracking. Designed to disappear into the moment.',
    },
  ],
} as const;

export type Feature = (typeof site.features)[number];
