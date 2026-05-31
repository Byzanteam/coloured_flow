import { act, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it } from "vitest"

import ThemeToggle from "./ThemeToggle"

describe("ThemeToggle", () => {
  beforeEach(() => {
    window.localStorage.clear()
    document.documentElement.removeAttribute("data-theme")
    document.documentElement.removeAttribute("data-mode")
  })
  afterEach(() => {
    document.documentElement.removeAttribute("data-theme")
    document.documentElement.removeAttribute("data-mode")
  })

  it("Cycles system → dark → light → system and persists in localStorage", () => {
    render(<ThemeToggle />)
    const button = screen.getByTestId("theme-toggle")

    expect(button.getAttribute("data-theme-current")).toBe("system")

    act(() => button.click())
    expect(button.getAttribute("data-theme-current")).toBe("dark")
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark")
    expect(document.documentElement.getAttribute("data-mode")).toBe("dark")
    expect(window.localStorage.getItem("cf-theme")).toBe("dark")

    act(() => button.click())
    expect(button.getAttribute("data-theme-current")).toBe("light")
    expect(document.documentElement.getAttribute("data-theme")).toBe("light")
    expect(document.documentElement.getAttribute("data-mode")).toBe("light")

    act(() => button.click())
    expect(button.getAttribute("data-theme-current")).toBe("system")
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false)
  })
})
