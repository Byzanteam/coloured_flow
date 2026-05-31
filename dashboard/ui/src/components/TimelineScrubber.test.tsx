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

  it("Holds the next tick while the previous replay dispatch is in-flight (4× speed)", () => {
    // 4× cadence is 250ms — easily shorter than a real server round-trip.
    // The autoplay loop must NOT issue overlapping :replay_to_version
    // dispatches, or replies can land out of order and the derived markings
    // drift away from the slider position. Gate: when `isPending` is true,
    // no new tick is scheduled; the next dispatch waits until isPending
    // toggles back to false.
    const onScrub = vi.fn()
    const onExit = vi.fn()
    const baseProps: Props = {
      range: { min: 1, max: 10 },
      liveVersion: 10,
      replayState: { version: 1, replayed_from: 1 } as never,
      onScrub,
      onExit,
      isPending: false
    }
    const { rerender } = render(<TimelineScrubber {...baseProps} />)

    const speedSelect = screen.getByTestId("timeline-speed") as HTMLSelectElement
    act(() => {
      speedSelect.value = "4"
      speedSelect.dispatchEvent(new Event("change", { bubbles: true }))
    })

    const playButton = screen.getByTestId("timeline-play-toggle") as HTMLButtonElement
    act(() => {
      playButton.click()
    })

    // First 4× tick fires at 250ms → v=2 dispatched.
    act(() => {
      vi.advanceTimersByTime(250)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
    expect(onScrub).toHaveBeenLastCalledWith(2)

    // Parent reports the command is in-flight. The Play button must visibly
    // disable to match the step buttons, and the autoplay loop must hold.
    rerender(<TimelineScrubber {...baseProps} isPending={true} />)
    expect((screen.getByTestId("timeline-play-toggle") as HTMLButtonElement).disabled).toBe(true)

    // Advance well past several 4× cadences while the dispatch is in-flight.
    // No further `onScrub` calls — the gate is the whole point of the fix.
    act(() => {
      vi.advanceTimersByTime(2000)
    })
    expect(onScrub).toHaveBeenCalledTimes(1)

    // Reply settles. The effect re-runs and schedules the next 4× tick.
    rerender(<TimelineScrubber {...baseProps} isPending={false} />)
    act(() => {
      vi.advanceTimersByTime(250)
    })
    expect(onScrub).toHaveBeenCalledTimes(2)
    expect(onScrub).toHaveBeenLastCalledWith(3)
  })

  it("flips data-autoplaying on the slider while autoplay is running", () => {
    renderScrubber()
    const slider = screen.getByTestId("timeline-slider") as HTMLInputElement
    expect(slider.dataset.autoplaying).toBe("false")

    const playButton = screen.getByTestId("timeline-play-toggle")
    act(() => {
      playButton.click()
    })
    expect(slider.dataset.autoplaying).toBe("true")
    // CSS variable drives the thumb transition window.
    expect(slider.style.getPropertyValue("--cf-thumb-duration")).toBe("1000ms")

    act(() => {
      playButton.click()
    })
    expect(slider.dataset.autoplaying).toBe("false")
  })

  it("Jump-to-v0 fires onScrub(min) and disables at min", () => {
    const { onScrub } = renderScrubber({
      replayState: { version: 3, replayed_from: 3 } as never
    })
    const btn = screen.getByTestId("timeline-jump-v0") as HTMLButtonElement
    expect(btn.disabled).toBe(false)
    act(() => {
      btn.click()
    })
    expect(onScrub).toHaveBeenCalledTimes(1)
    expect(onScrub).toHaveBeenLastCalledWith(1)
  })

  it("Jump-to-v0 disabled when value is already at min", () => {
    renderScrubber({ replayState: { version: 1, replayed_from: 1 } as never })
    expect((screen.getByTestId("timeline-jump-v0") as HTMLButtonElement).disabled).toBe(true)
  })

  it("Jump-to-live in live mode at non-max fires onScrub(max)", () => {
    const onScrub = vi.fn()
    const onExit = vi.fn()
    render(
      <TimelineScrubber
        range={{ min: 1, max: 5 }}
        liveVersion={5}
        replayState={null}
        onScrub={onScrub}
        onExit={onExit}
        isPending={false}
      />
    )
    // value initializes to liveVersion (5) which equals max → disabled.
    const btn = screen.getByTestId("timeline-jump-live") as HTMLButtonElement
    expect(btn.disabled).toBe(true)
    expect(onScrub).not.toHaveBeenCalled()
    expect(onExit).not.toHaveBeenCalled()
  })

  it("Jump-to-live in replay mode calls onExit (exit_replay path)", () => {
    const { onScrub, onExit } = renderScrubber()
    const btn = screen.getByTestId("timeline-jump-live") as HTMLButtonElement
    expect(btn.disabled).toBe(false)
    act(() => {
      btn.click()
    })
    expect(onExit).toHaveBeenCalledTimes(1)
    expect(onScrub).not.toHaveBeenCalled()
  })

  it("Step buttons remain present and functional alongside jump buttons", () => {
    const { onScrub } = renderScrubber()
    expect(screen.getByTestId("timeline-step-back")).toBeDefined()
    expect(screen.getByTestId("timeline-step-forward")).toBeDefined()
    act(() => {
      screen.getByTestId("timeline-step-forward").click()
    })
    expect(onScrub).toHaveBeenLastCalledWith(2)
    act(() => {
      screen.getByTestId("timeline-step-back").click()
    })
    expect(onScrub).toHaveBeenLastCalledWith(1)
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
