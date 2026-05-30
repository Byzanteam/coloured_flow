import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Button, LayerCard, Text } from "@cloudflare/kumo"
import {
  CaretLeftIcon,
  CaretRightIcon,
  PauseIcon,
  PlayIcon
} from "@phosphor-icons/react"

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

type SpeedKey = "0.25" | "1" | "4"
const SPEED_TICK_MS: Record<SpeedKey, number> = {
  "0.25": 4000,
  "1": 1000,
  "4": 250
}
const SPEED_OPTIONS: ReadonlyArray<{ value: SpeedKey; label: string }> = [
  { value: "0.25", label: "0.25×" },
  { value: "1", label: "1×" },
  { value: "4", label: "4×" }
]

/**
 * Step-through scrubber. Drag the slider to replay history at any version;
 * Play advances the version client-side at the chosen cadence (0.25× / 1×
 * / 4×). Speed changes take effect on the NEXT tick (the current scheduled
 * tick keeps the old interval) so the cadence is observable.
 *
 * Scrub dispatch is debounced ~150ms; Step / Play emit immediately so the
 * autoplay tick is deterministic. The loop lives in React (`setTimeout`),
 * not on the server — replay is a derived read-only view.
 *
 * Autoplay is gated on `isPending`: when a replay dispatch is in-flight, the
 * tick that would schedule the NEXT dispatch is held until the reply settles
 * (the effect re-runs on `isPending: true → false` and re-schedules). This
 * prevents overlapping `:replay_to_version` commands at 4× (250ms) where the
 * tick interval can be shorter than the round-trip, which would otherwise
 * let replies land out of order and drift the derived markings.
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

  const initialValue = replayState?.version ?? liveVersion ?? max
  const [value, setValue] = useState<number>(clamp(initialValue, min, max))
  const [speed, setSpeed] = useState<SpeedKey>("1")
  const [playing, setPlaying] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const playTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const speedRef = useRef(speed)

  // Speed is held in a ref so a mid-flight tick's interval is NOT mutated by
  // a speed change — only the next schedule reads the new cadence.
  useEffect(() => {
    speedRef.current = speed
  }, [speed])

  useEffect(() => {
    const next = clamp(replayState?.version ?? liveVersion ?? max, min, max)
    setValue(next)
  }, [replayState?.version, liveVersion, min, max])

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      if (playTimerRef.current) clearTimeout(playTimerRef.current)
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
    if (playing) setPlaying(false)
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    // Home / End jump to extremes; native range input already steps on
    // ArrowLeft / ArrowRight, so the keyboard story is complete here.
    if (event.key === "Home") {
      event.preventDefault()
      const next = min
      if (next !== value) {
        setValue(next)
        fireImmediate(next)
        if (playing) setPlaying(false)
      }
    } else if (event.key === "End") {
      event.preventDefault()
      const next = max
      if (next !== value) {
        setValue(next)
        fireImmediate(next)
        if (playing) setPlaying(false)
      }
    }
  }

  const onStep = (delta: number) => {
    const next = clamp(value + delta, min, max)
    if (next === value) return
    setValue(next)
    fireImmediate(next)
    if (playing) setPlaying(false)
  }

  // Autoplay loop. Each effect run schedules at most ONE tick; after the
  // tick fires it dispatches via `fireImmediate` and bumps `value`. The
  // value change re-runs this effect, which either schedules the next tick
  // (if `!isPending`) or holds until the parent's `:replay_to_version`
  // reply lands and toggles `isPending` back to false.
  //
  // `speedRef.current` is read at schedule time, so a mid-flight speed
  // change does not disturb the pending tick — the NEXT schedule picks up
  // the new cadence. Pauses on reaching `max`.
  useEffect(() => {
    if (!playing) return
    if (disabled) {
      setPlaying(false)
      return
    }
    if (value >= max) {
      setPlaying(false)
      return
    }
    if (isPending) return

    const id = setTimeout(() => {
      const next = clamp(value + 1, min, max)
      setValue(next)
      fireImmediate(next)
    }, SPEED_TICK_MS[speedRef.current])
    playTimerRef.current = id
    return () => {
      clearTimeout(id)
      if (playTimerRef.current === id) playTimerRef.current = null
    }
  }, [playing, isPending, value, max, min, disabled, fireImmediate])

  const onTogglePlay = () => {
    if (disabled) return
    if (playing) {
      setPlaying(false)
      return
    }
    if (value >= max) return
    setPlaying(true)
  }

  const atEnd = !disabled && value >= max

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
        <div className="flex items-center gap-2">
          {atEnd ? (
            <span
              className="text-xs text-cf-ink-faint"
              data-testid="timeline-end-caption"
            >
              End of timeline
            </span>
          ) : null}
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
          onKeyDown={onKeyDown}
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
        <Button
          variant={playing ? "secondary" : "primary"}
          size="sm"
          onClick={onTogglePlay}
          disabled={disabled || atEnd || isPending}
          aria-label={playing ? "Pause autoplay" : "Play autoplay"}
          aria-pressed={playing}
          data-testid="timeline-play-toggle"
        >
          {playing ? (
            <PauseIcon size={14} weight="bold" aria-hidden />
          ) : (
            <PlayIcon size={14} weight="bold" aria-hidden />
          )}
        </Button>
        <label className="flex items-center gap-1.5">
          <span className="sr-only">Playback speed</span>
          <select
            className="h-8 rounded-md border border-cf-border bg-cf-surface px-2 text-xs font-medium text-cf-ink tabular-nums transition-colors hover:border-cf-border-strong disabled:cursor-not-allowed disabled:opacity-50"
            value={speed}
            onChange={(event) => setSpeed(event.target.value as SpeedKey)}
            disabled={disabled}
            aria-label="Playback speed"
            data-testid="timeline-speed"
          >
            {SPEED_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </label>
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
