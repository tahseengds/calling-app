'use client';

import { Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import { Float } from '@react-three/drei';
import { EffectComposer, Bloom, Vignette } from '@react-three/postprocessing';
import { Phone } from './Phone';
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
      camera={{ position: [0, 0, 7], fov: 34 }}
      frameloop={reduced ? 'demand' : 'always'}
      performance={{ min: 0.5 }}
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[4, 6, 5]} intensity={2.2} />
      <pointLight position={[-5, 2, 3]} intensity={26} color="#7c5cff" />
      <pointLight position={[5, -2, 2]} intensity={18} color="#46e0d0" />
      <pointLight position={[0, 3, -4]} intensity={14} color="#6d7cff" />

      <Suspense fallback={null}>
        <group position={[isMobile ? 0 : 1.6, 0, 0]}>
          <Float
            speed={reduced ? 0 : 1.3}
            rotationIntensity={reduced ? 0 : 0.35}
            floatIntensity={reduced ? 0 : 0.9}
          >
            <Phone />
          </Float>
        </group>
        <Particles count={isMobile ? 350 : 900} />
      </Suspense>

      {!isMobile && !reduced && (
        <EffectComposer>
          <Bloom
            intensity={0.85}
            luminanceThreshold={0.22}
            luminanceSmoothing={0.4}
            mipmapBlur
          />
          <Vignette offset={0.25} darkness={0.72} eskil={false} />
        </EffectComposer>
      )}
    </Canvas>
  );
}
