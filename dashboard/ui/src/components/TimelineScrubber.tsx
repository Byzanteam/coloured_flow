import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Button, LayerCard, Text } from "@cloudflare/kumo"
import { CaretLeftIcon, CaretRightIcon } from "@phosphor-icons/react"

type VersionRange = ColouredFlowDashboardWeb.Views.VersionRange
type ReplayState = ColouredFlowDashboardWeb.Views.ReplayState

interface TimelineScrubberProps {
  range: VersionRange
  liveVersion: number
  replayState: ReplayState | null
  onScrub: (version: number) => void
  onExit: () => void
  isPending: boolean
}

const DEBOUNCE_MS = 150

/**
 * M7a timeline scrubber. Lets the operator drag a slider across the
 * `[range.min, range.max]` window to replay markings at an earlier version.
 *
 * Dispatch is debounced ~150ms so dragging across the range does not
 * fan out one server round-trip per pixel. Step buttons flank the slider
 * for keyboard-friendly single-version moves. A "Return to live" affordance
 * appears only while `replayState !== null` so the live state has no extra
 * chrome.
 */
export default function TimelineScrubber({
  range,
  liveVersion,
  replayState,
  onScrub,
  onExit,
  isPending
}: TimelineScrubberProps) {
  const min = Math.max(0, range.min)
  const max = Math.max(min, range.max)
  const disabled = max <= min
  const replayActive = replayState !== null

  // Local slider position so the thumb tracks the user's input without
  // waiting for a server reply. Synced from props when no drag is in flight.
  const initialValue = replayState?.version ?? liveVersion ?? max
  const [value, setValue] = useState<number>(clamp(initialValue, min, max))
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const next = clamp(replayState?.version ?? liveVersion ?? max, min, max)
    setValue(next)
  }, [replayState?.version, liveVersion, min, max])

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [])

  const schedule = useCallback(
    (next: number) => {
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = setTimeout(() => {
        onScrub(next)
      }, DEBOUNCE_MS)
    },
    [onScrub]
  )

  const fireImmediate = useCallback(
    (next: number) => {
      if (timerRef.current) {
        clearTimeout(timerRef.current)
        timerRef.current = null
      }
      onScrub(next)
    },
    [onScrub]
  )

  const onChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const next = clamp(parseInt(event.target.value, 10) || min, min, max)
    setValue(next)
    schedule(next)
  }

  const onStep = (delta: number) => {
    const next = clamp(value + delta, min, max)
    if (next === value) return
    setValue(next)
    fireImmediate(next)
  }

  const caption = useMemo(() => {
    if (replayActive) {
      return `Replay · v${replayState.version} of v${max}`
    }
    return `Live · v${liveVersion}`
  }, [replayActive, replayState, liveVersion, max])

  return (
    <LayerCard.Primary
      className="flex flex-col gap-3 px-4 py-3"
      data-testid="timeline-scrubber"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <Text variant="secondary">Timeline</Text>
          <span
            className="truncate text-sm text-cf-ink tabular-nums"
            data-testid="timeline-caption"
          >
            {caption}
          </span>
        </div>
        {replayActive ? (
          <Button
            variant="secondary"
            size="sm"
            onClick={onExit}
            data-testid="timeline-exit-replay"
          >
            Return to live
          </Button>
        ) : null}
      </div>
      <div className="flex items-center gap-2">
        <Button
          variant="secondary"
          size="sm"
          onClick={() => onStep(-1)}
          disabled={disabled || value <= min || isPending}
          aria-label="Step back one version"
          data-testid="timeline-step-back"
        >
          <CaretLeftIcon size={14} weight="bold" aria-hidden />
        </Button>
        <input
          type="range"
          min={min}
          max={max}
          step={1}
          value={value}
          onChange={onChange}
          disabled={disabled}
          aria-valuemin={min}
          aria-valuemax={max}
          aria-valuenow={value}
          aria-label="Timeline scrubber"
          data-testid="timeline-slider"
          className="cf-timeline-slider w-full"
        />
        <Button
          variant="secondary"
          size="sm"
          onClick={() => onStep(1)}
          disabled={disabled || value >= max || isPending}
          aria-label="Step forward one version"
          data-testid="timeline-step-forward"
        >
          <CaretRightIcon size={14} weight="bold" aria-hidden />
        </Button>
      </div>
      <div className="flex justify-between text-xs text-cf-ink-faint tabular-nums">
        <span>v{min}</span>
        <span>v{max}</span>
      </div>
    </LayerCard.Primary>
  )
}

function clamp(value: number, min: number, max: number): number {
  if (Number.isNaN(value)) return min
  if (value < min) return min
  if (value > max) return max
  return value
}
