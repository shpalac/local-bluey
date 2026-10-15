import { useEffect, useState } from 'react';
import { useRive, useStateMachineInput } from '@rive-app/react-canvas';

interface MascotProps {
  src: string;
  fallbackSrc: string;
}

function AnimatedMascot({ src }: { src: string }) {
  const [hovering, setHovering] = useState(false);
  const { rive, RiveComponent } = useRive({
    src,
    stateMachines: 'Bluey',
    autoplay: true,
  });
  const hoverInput = useStateMachineInput(rive, 'Bluey', 'hover');

  useEffect(() => {
    if (hoverInput) hoverInput.value = hovering;
  }, [hoverInput, hovering]);

  return (
    <div className="rive-stage" onPointerEnter={() => setHovering(true)} onPointerLeave={() => setHovering(false)}>
      <RiveComponent aria-label="Animated Bluey character" role="img" />
    </div>
  );
}

export default function RiveMascot({ src, fallbackSrc }: MascotProps) {
  // Rive is intentionally opt-in: the repository has no approved .riv asset.
  if (src && src.endsWith('.riv')) return <AnimatedMascot src={src} />;
  return (
    <img
      className="mascot-image"
      src={fallbackSrc}
      alt="Joyful Bluey bird with wide eyes, orange beak and welcoming wings"
      width={580}
      height={580}
      decoding="async"
      fetchPriority="high"
    />
  );
}
