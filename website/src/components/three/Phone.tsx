'use client';

import { useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { RoundedBox } from '@react-three/drei';
import * as THREE from 'three';

const vertexShader = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

// Animated "app screen": cool dark base with a slow brand-blue glow + faint rows.
const fragmentShader = /* glsl */ `
  varying vec2 vUv;
  uniform float uTime;
  void main() {
    vec2 uv = vUv;
    vec3 dark = vec3(0.031, 0.035, 0.047);
    vec3 blue = vec3(0.184, 0.420, 1.0);
    vec3 bone = vec3(0.93, 0.945, 0.97);
    float t = uv.y + 0.15 * sin(uv.x * 6.0 + uTime * 0.8);
    vec3 col = mix(dark, blue, smoothstep(0.15, 1.0, t) * 0.62);
    col += bone * (0.05 + 0.05 * sin(uTime * 0.5 + uv.y * 3.0)) * smoothstep(0.6, 1.0, t);
    float rows = smoothstep(0.02, 0.0, abs(fract(uv.y * 9.0 - uTime * 0.04) - 0.5) - 0.36);
    col += rows * 0.05;
    float v = smoothstep(1.1, 0.2, length(uv - 0.5));
    col *= 0.82 + 0.30 * v;
    gl_FragColor = vec4(col, 1.0);
  }
`;

export function Phone() {
  const group = useRef<THREE.Group>(null);
  const mat = useRef<THREE.ShaderMaterial>(null);
  const uniforms = useMemo(() => ({ uTime: { value: 0 } }), []);

  useFrame((state, delta) => {
    if (mat.current) mat.current.uniforms.uTime.value = state.clock.elapsedTime;
    if (!group.current) return;
    // Gentle idle spin + parallax lean toward the pointer.
    const { x, y } = state.pointer;
    group.current.rotation.y +=
      (x * 0.5 + Math.sin(state.clock.elapsedTime * 0.25) * 0.18 - group.current.rotation.y) *
      Math.min(1, delta * 2);
    group.current.rotation.x +=
      (-y * 0.3 - group.current.rotation.x) * Math.min(1, delta * 2);
  });

  return (
    <group ref={group} rotation={[0, 0, 0]} scale={1}>
      {/* Body */}
      <RoundedBox args={[1.62, 3.34, 0.2]} radius={0.18} smoothness={8} castShadow>
        <meshStandardMaterial color="#101116" metalness={0.9} roughness={0.28} />
      </RoundedBox>

      {/* Side rail highlight */}
      <RoundedBox args={[1.68, 3.4, 0.16]} radius={0.2} smoothness={6}>
        <meshStandardMaterial
          color="#2b2e3a"
          metalness={1}
          roughness={0.35}
          transparent
          opacity={0.35}
        />
      </RoundedBox>

      {/* Screen */}
      <mesh position={[0, 0, 0.108]}>
        <planeGeometry args={[1.42, 3.12]} />
        <shaderMaterial
          ref={mat}
          uniforms={uniforms}
          vertexShader={vertexShader}
          fragmentShader={fragmentShader}
          toneMapped={false}
        />
      </mesh>

      {/* Screen glass sheen */}
      <mesh position={[0, 0, 0.112]}>
        <planeGeometry args={[1.42, 3.12]} />
        <meshBasicMaterial color="#ffffff" transparent opacity={0.04} />
      </mesh>

      {/* Camera dot */}
      <mesh position={[0, 1.42, 0.12]}>
        <circleGeometry args={[0.045, 24]} />
        <meshStandardMaterial color="#08090c" metalness={1} roughness={0.2} />
      </mesh>
    </group>
  );
}
