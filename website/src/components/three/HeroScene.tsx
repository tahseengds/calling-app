'use client';

import { Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import { EffectComposer, Bloom, Vignette } from '@react-three/postprocessing';
import { Particles } from './Particles';
import { useIsMobile, usePrefersReducedMotion } from '@/hooks/useMediaQuery';

export default function HeroScene() {
  const isMobile = useIsMobile();
  const reduced = usePrefersReducedMotion();

  return (
    <Canvas
      className="!absolute inset-0"
      dpr={isMobile ? [1, 1.5] : [1, 2]}
      gl={{ antialias: true, alpha: true, powerPreference: 'high-performance' }}
      camera={{ position: [0, 0, 7], fov: 50 }}
      frameloop={reduced ? 'demand' : 'always'}
      performance={{ min: 0.5 }}
    >
      <ambientLight intensity={0.35} />
      <pointLight position={[-5, 2, 3]} intensity={18} color="#2f6bff" />
      <pointLight position={[5, -2, 2]} intensity={12} color="#7aa5ff" />

      <Suspense fallback={null}>
        <Particles count={isMobile ? 300 : 700} />
      </Suspense>

      {!isMobile && !reduced && (
        <EffectComposer>
          <Bloom
            intensity={0.55}
            luminanceThreshold={0.3}
            luminanceSmoothing={0.4}
            mipmapBlur
          />
          <Vignette offset={0.25} darkness={0.6} eskil={false} />
        </EffectComposer>
      )}
    </Canvas>
  );
}
