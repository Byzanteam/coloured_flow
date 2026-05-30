import type { CSSProperties, ReactNode } from "react"
import { motion } from "motion/react"

import { cn } from "../../lib/utils"

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
  const composedStyle: CSSProperties = {
    backgroundImage:
      "linear-gradient(110deg, var(--color-cf-ink) 0%, var(--color-cf-ink) 42%, var(--color-cf-accent) 50%, var(--color-cf-ink) 58%, var(--color-cf-ink) 100%)",
    backgroundSize: `${shimmerWidth * 2}% 100%`,
    backgroundRepeat: "no-repeat",
    WebkitBackgroundClip: "text",
    WebkitTextFillColor: "transparent",
    ...style
  }

  return (
    <motion.span
      data-testid="animated-shiny-text"
      {...props}
      className={cn("inline-block bg-clip-text text-transparent", className)}
      style={composedStyle}
      animate={{ backgroundPosition: ["150% 0%", "-50% 0%"] }}
      transition={{ duration, ease: "linear", repeat: Infinity }}
    >
      {children}
    </motion.span>
  )
}
