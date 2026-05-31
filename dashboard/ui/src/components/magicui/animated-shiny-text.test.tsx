import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { AnimatedShinyText } from "./animated-shiny-text"

describe("AnimatedShinyText", () => {
  it("renders the children as bg-clipped text", () => {
    render(<AnimatedShinyText>v1.2.3</AnimatedShinyText>)
    const node = screen.getByTestId("animated-shiny-text")
    expect(node.textContent).toBe("v1.2.3")
    expect(node.className).toContain("bg-clip-text")
    expect(node.className).toContain("text-transparent")
  })

  it("merges custom classNames", () => {
    render(<AnimatedShinyText className="text-xs italic">x</AnimatedShinyText>)
    const node = screen.getByTestId("animated-shiny-text")
    expect(node.className).toContain("text-xs")
    expect(node.className).toContain("italic")
  })

  it("scales the background size by shimmerWidth", () => {
    render(<AnimatedShinyText shimmerWidth={50}>x</AnimatedShinyText>)
    const node = screen.getByTestId("animated-shiny-text") as HTMLElement
    expect(node.style.backgroundSize).toBe("100% 100%")
  })
})
