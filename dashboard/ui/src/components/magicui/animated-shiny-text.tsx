import type { CSSProperties, ReactNode } from "react"

interface AnimatedShinyTextProps {
  children: ReactNode
  className?: string
  shimmerWidth?: number
  duration?: number
  style?: CSSProperties
  "aria-label"?: string
}

export function AnimatedShinyText({
  children,
  className,
  shimmerWidth = 120,
  duration = 4,
  style,
  ...props
}: AnimatedShinyTextProps) {
  const composedStyle = {
    backgroundImage:
      "linear-gradient(110deg, var(--color-cf-ink) 0%, var(--color-cf-ink) 42%, var(--color-cf-accent) 50%, var(--color-cf-ink) 58%, var(--color-cf-ink) 100%)",
    backgroundSize: `${shimmerWidth * 2}% 100%`,
    "--cf-shimmer-duration": `${duration}s`,
    ...style
  } as CSSProperties

  const composedClass = ["cf-shimmer-text bg-clip-text text-transparent", className]
    .filter(Boolean)
    .join(" ")

  return (
    <span
      data-testid="animated-shiny-text"
      {...props}
      className={composedClass}
      style={composedStyle}
    >
      {children}
    </span>
  )
}
