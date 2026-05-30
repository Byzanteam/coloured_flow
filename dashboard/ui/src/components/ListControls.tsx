import { type ReactNode, useId } from "react"
import { InputGroup } from "@cloudflare/kumo"
import { MagnifyingGlassIcon } from "@phosphor-icons/react"

import { LIST_PAGE_SIZE_OPTIONS } from "../hooks/useListSearchParams"

export interface ListControlsProps {
  q: string
  onQChange: (next: string) => void
  searchPlaceholder?: string
  searchLabel?: string
  pageSize: number
  onPageSizeChange: (next: number) => void
  pageSizeOptions?: readonly number[]
  /** Page-specific filters rendered between search and page size. */
  children?: ReactNode
}

/**
 * Sticky controls row for list/grid pages. Holds the search input on the
 * left, page-specific filters in the middle (children slot), and the
 * page-size selector on the right. URL state lives in `useListSearchParams`;
 * this component is purely presentational.
 */
export default function ListControls({
  q,
  onQChange,
  searchPlaceholder = "Search…",
  searchLabel = "Search",
  pageSize,
  onPageSizeChange,
  pageSizeOptions = LIST_PAGE_SIZE_OPTIONS,
  children
}: ListControlsProps) {
  const selectId = useId()

  return (
    <div
      className="sticky top-0 z-10 flex flex-wrap items-center gap-3 rounded-xl border border-cf-border bg-cf-surface/95 px-4 py-3 backdrop-blur"
      data-testid="list-controls"
    >
      <div className="min-w-[14rem] flex-1">
        <InputGroup size="sm" className="w-full">
          <InputGroup.Addon>
            <MagnifyingGlassIcon size={14} aria-hidden />
          </InputGroup.Addon>
          <InputGroup.Input
            type="search"
            value={q}
            onChange={(event) => onQChange(event.target.value)}
            placeholder={searchPlaceholder}
            aria-label={searchLabel}
            data-testid="list-controls-search"
          />
        </InputGroup>
      </div>

      {children ? (
        <div className="flex flex-wrap items-center gap-2">{children}</div>
      ) : null}

      <label
        htmlFor={selectId}
        className="ml-auto flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted"
      >
        Page size
        <select
          id={selectId}
          className="h-7 rounded-md border border-cf-border bg-cf-surface px-2 text-xs font-medium text-cf-ink outline-none focus:ring-[1.5px] focus:ring-kumo-focus/50"
          value={pageSize}
          onChange={(event) => onPageSizeChange(Number(event.target.value))}
          aria-label="Page size"
          data-testid="list-controls-page-size"
        >
          {pageSizeOptions.map((size) => (
            <option key={size} value={size}>
              {size}
            </option>
          ))}
        </select>
      </label>
    </div>
  )
}
