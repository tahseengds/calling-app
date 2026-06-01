/** Cool editorial surface (replaces glassmorphism). Hairline + tinted depth. */
export function GlassCard({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <div className={`surface rounded-lg shadow-card ${className}`}>{children}</div>;
}
