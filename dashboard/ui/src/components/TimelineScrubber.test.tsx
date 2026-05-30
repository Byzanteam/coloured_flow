import { act, render, screen } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import TimelineScrubber from "./TimelineScrubber"

type Props = Parameters<typeof TimelineScrubber>[0]

function renderScrubber(overrides: Partial<Props> = {}) {
  const onScrub = vi.fn()
  const onExit = vi.fn()
  const props: Props = {
    range: { min: 1, max: 5 },
    liveVersion: 5,
    replayState: { version: 1, replayed_from: 1 } as never,
    onScrub,
    onExit,
    isPending: false,
    ...overrides
  }
  const result = render(<TimelineScrubber {...props} />)
  return { ...result, onScrub, onExit, props }
}

describe("TimelineScrubber autoplay", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it("Play advances version at 1x cadence and Pause stops further ticks", () => {
    const { onScrub } = renderScrubber()
    const playButton = screen.getByTestId("timeline-play-toggle")

    act(() => {
      playButton.click()
    })

    expect(onScrub).not.toHaveBeenCalled()

    act(() => {
      vi.advanceTimersByTime(1000)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
    expect(onScrub).toHaveBeenLastCalledWith(2)

    act(() => {
      vi.advanceTimersByTime(1000)
    })
    expect(onScrub).toHaveBeenCalledTimes(2)
    expect(onScrub).toHaveBeenLastCalledWith(3)

    act(() => {
      playButton.click()
    })

    act(() => {
      vi.advanceTimersByTime(5000)
    })
    expect(onScrub).toHaveBeenCalledTimes(2)
  })

  it("Speed change applies on the next tick, not the in-flight one", () => {
    const { onScrub } = renderScrubber()
    const playButton = screen.getByTestId("timeline-play-toggle")
    const speedSelect = screen.getByTestId("timeline-speed") as HTMLSelectElement

    act(() => {
      playButton.click()
    })

    // Mid-flight speed change at t=500 with a 1×-scheduled tick at t=1000:
    // the in-flight tick MUST still fire on its original 1000ms schedule.
    act(() => {
      vi.advanceTimersByTime(500)
    })
    act(() => {
      speedSelect.value = "4"
      speedSelect.dispatchEvent(new Event("change", { bubbles: true }))
    })

    // Less than 1000ms total → still no call (in-flight tick has not fired).
    act(() => {
      vi.advanceTimersByTime(400)
    })
    expect(onScrub).toHaveBeenCalledTimes(0)

    // Cross the 1000ms boundary → the in-flight 1× tick fires.
    act(() => {
      vi.advanceTimersByTime(100)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
    expect(onScrub).toHaveBeenLastCalledWith(2)

    // Next tick uses the new 250ms cadence.
    act(() => {
      vi.advanceTimersByTime(250)
    })
    expect(onScrub).toHaveBeenCalledTimes(2)
    expect(onScrub).toHaveBeenLastCalledWith(3)
  })

  it("Stops at the end of the range and surfaces the End-of-timeline caption", () => {
    const { onScrub } = renderScrubber({
      replayState: { version: 4, replayed_from: 4 } as never
    })
    const playButton = screen.getByTestId("timeline-play-toggle")

    act(() => {
      playButton.click()
    })

    act(() => {
      vi.advanceTimersByTime(1000)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
    expect(onScrub).toHaveBeenLastCalledWith(5)

    expect(screen.getByTestId("timeline-end-caption").textContent).toMatch(/End of timeline/)
    expect((playButton as HTMLButtonElement).disabled).toBe(true)

    act(() => {
      vi.advanceTimersByTime(5000)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
  })

  it("Home / End jump to extremes via the slider", () => {
    const { onScrub } = renderScrubber()
    const slider = screen.getByTestId("timeline-slider")

    act(() => {
      slider.dispatchEvent(
        new KeyboardEvent("keydown", { key: "End", bubbles: true })
      )
    })
    expect(onScrub).toHaveBeenLastCalledWith(5)

    act(() => {
      slider.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Home", bubbles: true })
      )
    })
    expect(onScrub).toHaveBeenLastCalledWith(1)
  })
})
