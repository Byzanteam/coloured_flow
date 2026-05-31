import type { CSSProperties, ReactNode } from "react"

interface AuroraTextProps {
  children: ReactNode
  className?: string
  colors?: string[]
  speed?: number
  "aria-label"?: string
}

const DEFAULT_COLORS = [
  "var(--color-cf-accent)",
  "var(--color-cf-accent-ink)",
  "var(--color-cf-ink)",
  "var(--color-cf-accent)"
]

export function AuroraText({
  children,
  className,
  colors = DEFAULT_COLORS,
  speed = 1,
  ...props
}: AuroraTextProps) {
  const gradient = `linear-gradient(110deg, ${[...colors, colors[0]].join(", ")})`
  const wrapperClass = ["relative inline-block", className].filter(Boolean).join(" ")
  const style = {
    backgroundImage: gradient,
    "--cf-aurora-duration": `${8 / speed}s`
  } as CSSProperties

  return (
    <span data-testid="aurora-text" className={wrapperClass} {...props}>
      <span className="sr-only">{children}</span>
      <span aria-hidden="true" className="cf-aurora-text" style={style}>
        {children}
      </span>
    </span>
  )
}
