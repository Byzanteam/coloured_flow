import { act, render, screen } from "@testing-library/react"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { describe, expect, it } from "vitest"

import { useEmbedMode } from "./useEmbedMode"

function Probe() {
  const { embed, exit } = useEmbedMode()
  return (
    <div>
      <span data-testid="embed-flag">{embed ? "yes" : "no"}</span>
      <button data-testid="exit" onClick={exit}>
        exit
      </button>
    </div>
  )
}

describe("useEmbedMode", () => {
  it("reports `yes` when embed=1 is on the URL", () => {
    render(
      <MemoryRouter initialEntries={["/enactments/abc?embed=1&foo=bar"]}>
        <Routes>
          <Route path="/enactments/:id" element={<Probe />} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByTestId("embed-flag").textContent).toBe("yes")
  })

  it("`exit` strips embed from the URL while preserving siblings", () => {
    render(
      <MemoryRouter initialEntries={["/x?embed=1&keep=ok"]}>
        <Routes>
          <Route path="/x" element={<Probe />} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByTestId("embed-flag").textContent).toBe("yes")
    act(() => {
      screen.getByTestId("exit").click()
    })
    expect(screen.getByTestId("embed-flag").textContent).toBe("no")
  })
})
