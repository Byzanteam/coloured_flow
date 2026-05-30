import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { AuroraText } from "./aurora-text"

describe("AuroraText", () => {
  it("renders the children text with a gradient overlay", () => {
    render(<AuroraText>CF</AuroraText>)
    const wrapper = screen.getByTestId("aurora-text")
    expect(wrapper.textContent).toContain("CF")
    expect(wrapper.className).toContain("inline-block")
  })

  it("applies a custom className without dropping base classes", () => {
    render(<AuroraText className="text-xl tracking-tight">Hello</AuroraText>)
    const wrapper = screen.getByTestId("aurora-text")
    expect(wrapper.className).toContain("text-xl")
    expect(wrapper.className).toContain("tracking-tight")
    expect(wrapper.className).toContain("inline-block")
  })

  it("uses the supplied colors in the gradient", () => {
    render(<AuroraText colors={["#fff", "#000"]}>x</AuroraText>)
    const wrapper = screen.getByTestId("aurora-text")
    const gradient = wrapper.querySelector("[aria-hidden=\"true\"]") as HTMLElement
    expect(gradient.style.backgroundImage).toContain("#fff")
    expect(gradient.style.backgroundImage).toContain("#000")
  })
})
