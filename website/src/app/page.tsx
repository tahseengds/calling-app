import { Hero } from '@/components/sections/Hero';
import { Features } from '@/components/sections/Features';
import { Experience } from '@/components/sections/Experience';
import { Stats } from '@/components/sections/Stats';
import { CTA } from '@/components/sections/CTA';
import { Footer } from '@/components/sections/Footer';

export default function Page() {
  return (
    <>
      <Hero />
      <Features />
      <Experience />
      <Stats />
      <CTA />
      <Footer />
    </>
  );
}
