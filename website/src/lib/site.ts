/** Single source of truth for copy + links, so sections stay declarative. */
export const site = {
  name: 'Lumio',
  tagline: 'Calls that feel like presence.',
  description:
    'A private place to chat, call and video with the people who matter. End-to-end encrypted, and quietly simple.',
  url: 'https://lumio.app',
  cta: {
    primary: { label: 'Get the app', href: '#download' },
    secondary: { label: 'Watch the film', href: '#experience' },
  },
  nav: [
    { label: 'Features', href: '#features' },
    { label: 'Experience', href: '#experience' },
    { label: 'Download', href: '#download' },
  ],
  // Honest, non-fake-precise claims. Treat as marketing copy, not measured data.
  stats: [
    { value: '4K', label: 'adaptive video' },
    { value: 'E2E', label: 'encrypted, always' },
    { value: '0', label: 'ads or trackers' },
    { value: '3', label: 'devices, in sync' },
  ],
  features: [
    {
      title: 'Crystal voice and video',
      body: 'Adaptive 4K video and studio-grade audio that hold up on a train, in a tunnel, or in a loud cafe.',
      icon: 'video',
    },
    {
      title: 'Private by design',
      body: 'Every message and call is end-to-end encrypted. Your conversations never leave your circle.',
      icon: 'shield',
    },
    {
      title: 'Instant, everywhere',
      body: 'Calls connect in a blink and follow you across phone, tablet and desktop without dropping a beat.',
      icon: 'bolt',
    },
    {
      title: 'Expressive messaging',
      body: 'Reactions, stickers, voice notes and jumbo emoji. Say it the way it actually feels.',
      icon: 'spark',
    },
    {
      title: 'Picture-in-picture',
      body: 'Float a call into the corner and keep doing everything else. Presence without the friction.',
      icon: 'layers',
    },
    {
      title: 'Effortless groups',
      body: 'Family, friends, teams. Bring everyone in with a tap. No links, no logins, no fuss.',
      icon: 'people',
    },
  ],
  showcase: [
    {
      kicker: 'Conversations',
      title: 'A space that breathes',
      body: 'Threads that feel alive: typing presence, read state, reactions and media that load the instant you need them.',
    },
    {
      kicker: 'Calling',
      title: 'Be there, instantly',
      body: 'One tap to voice or video. Honest controls, real-time quality, and a ringtone that actually rings.',
    },
    {
      kicker: 'In your control',
      title: 'Yours, end to end',
      body: 'Granular privacy, on-device intelligence, and zero ad tracking. Built to disappear into the moment.',
    },
  ],
} as const;

export type Feature = (typeof site.features)[number];
