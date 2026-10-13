import { Canvas, useFrame } from '@react-three/fiber';
import { useEffect, useRef, useState } from 'react';
import type { Group } from 'three';

function OrbitSculpture() {
  const shape = useRef<Group>(null);
  useFrame(({ clock, pointer }, delta) => {
    if (!shape.current) return;
    const time = clock.getElapsedTime();
    shape.current.rotation.y += Math.min(delta, 0.04) * 0.07;
    shape.current.rotation.x += (pointer.y * 0.18 - shape.current.rotation.x) * 0.018;
    shape.current.rotation.z = Math.sin(time * 0.3) * 0.04 + pointer.x * 0.09;
  });

  return (
    <group ref={shape}>
      <ambientLight intensity={1.1} />
      <pointLight color="#eae0ff" intensity={35} position={[3, 3, 5]} />
      <pointLight color="#a0d3ff" intensity={22} position={[-3, -2, 3]} />
      <mesh rotation={[1.0, 0.25, -0.3]}>
        <torusGeometry args={[2.1, 0.036, 12, 120]} />
        <meshStandardMaterial color="#d9ef84" emissive="#7a9f31" emissiveIntensity={0.4} metalness={0.35} roughness={0.25} />
      </mesh>
      <mesh rotation={[0.3, 1.1, 0.35]}>
        <torusGeometry args={[2.42, 0.02, 12, 120]} />
        <meshStandardMaterial color="#bfc7fb" transparent opacity={0.55} metalness={0.3} roughness={0.4} />
      </mesh>
      {[
        [-2.1, 1.0, 0.8, 0.18],
        [2.2, -0.6, 0.2, 0.13],
        [1.2, 2.0, -0.4, 0.12],
        [-0.7, -2.3, 0.7, 0.1]
      ].map(([x, y, z, size], index) => (
        <mesh key={index} position={[x, y, z]}>
          <icosahedronGeometry args={[size, 1]} />
          <meshStandardMaterial color={index % 2 ? '#ddd4ff' : '#d5f58b'} metalness={0.25} roughness={0.28} />
        </mesh>
      ))}
    </group>
  );
}

export default function CompanionScene() {
  const [supported, setSupported] = useState(false);

  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const check = () => {
      if (media.matches || window.innerWidth < 760 || navigator.hardwareConcurrency <= 2) {
        setSupported(false);
        return;
      }
      const canvas = document.createElement('canvas');
      try {
        const context = canvas.getContext('webgl2') || canvas.getContext('webgl');
        setSupported(Boolean(context));
      } catch {
        setSupported(false);
      }
    };
    check();
    media.addEventListener('change', check);
    return () => media.removeEventListener('change', check);
  }, []);

  if (!supported) return null;

  return (
    <Canvas
      aria-hidden="true"
      dpr={[1, 1.5]}
      camera={{ position: [0, 0, 7.8], fov: 44 }}
      gl={{ alpha: true, antialias: false, powerPreference: 'low-power' }}
      style={{ width: '100%', height: '100%', pointerEvents: 'none' }}
      fallback={null}
    >
      <OrbitSculpture />
    </Canvas>
  );
}
