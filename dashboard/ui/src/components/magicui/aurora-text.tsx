import type { ReactNode } from "react"
import { motion } from "motion/react"

import { cn } from "../../lib/utils"

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

  return (
    <span
      data-testid="aurora-text"
      className={cn("relative inline-block", className)}
      {...props}
    >
      <span className="sr-only">{children}</span>
      <motion.span
        aria-hidden="true"
        className="bg-clip-text text-transparent"
        style={{
          backgroundImage: gradient,
          backgroundSize: "200% auto",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent"
        }}
        animate={{ backgroundPosition: ["0% 50%", "200% 50%"] }}
        transition={{ duration: 8 / speed, ease: "linear", repeat: Infinity }}
      >
        {children}
      </motion.span>
    </span>
  )
}
