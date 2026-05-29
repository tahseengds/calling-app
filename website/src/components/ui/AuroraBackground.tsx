'use client';

/**
 * Ambient animated mesh-gradient built from blurred, slowly drifting blobs.
 * Pure CSS/compositor work (transform + opacity), so it's smooth on every
 * device and never competes with the WebGL canvas for the GPU.
 */
export function AuroraBackground() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      <div className="absolute inset-0 opacity-90">
        <span className="absolute -left-1/4 top-[-10%] h-[55vw] w-[55vw] rounded-full bg-brand-glow/30 blur-[120px] animate-aurora" />
        <span className="absolute right-[-15%] top-[10%] h-[45vw] w-[45vw] rounded-full bg-brand-500/25 blur-[120px] animate-aurora [animation-delay:-6s]" />
        <span className="absolute bottom-[-20%] left-[20%] h-[50vw] w-[50vw] rounded-full bg-aqua/15 blur-[140px] animate-aurora [animation-delay:-11s]" />
      </div>
      {/* Fine grid for spatial depth, masked to fade out. */}
      <div
        className="absolute inset-0 opacity-[0.07] mask-fade-b"
        style={{
          backgroundImage:
            'linear-gradient(to right, rgba(255,255,255,0.6) 1px, transparent 1px), linear-gradient(to bottom, rgba(255,255,255,0.6) 1px, transparent 1px)',
          backgroundSize: '64px 64px',
        }}
      />
      {/* Vignette so content stays the focus. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,rgba(5,6,12,0.85)_100%)]" />
    </div>
  );
}
