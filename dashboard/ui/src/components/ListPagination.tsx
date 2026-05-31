import { useEffect } from "react"
import { Pagination } from "@cloudflare/kumo"

export interface ListPaginationProps {
  page: number
  pageSize: number
  totalCount: number
  filteredCount: number
  setPage: (next: number) => void
}

/**
 * Pagination footer paired with `ListControls`. Reads totals provided by the
 * page after filtering; renders Kumo's compound Pagination plus a
 * "showing m–n of total" summary. Auto-clamps `page` when the result set
 * shrinks below the current offset (e.g. live insertion drops count).
 */
export default function ListPagination({
  page,
  pageSize,
  totalCount,
  filteredCount,
  setPage
}: ListPaginationProps) {
  const totalPages = Math.max(1, Math.ceil(filteredCount / pageSize))
  const clampedPage = Math.min(Math.max(1, page), totalPages)

  useEffect(() => {
    if (clampedPage !== page) setPage(clampedPage)
  }, [clampedPage, page, setPage])

  if (filteredCount === 0) return null

  const startIndex = (clampedPage - 1) * pageSize
  const endIndex = Math.min(filteredCount, startIndex + pageSize)
  const showingLabel =
    filteredCount === totalCount
      ? `Showing ${startIndex + 1}–${endIndex} of ${totalCount}`
      : `Showing ${startIndex + 1}–${endIndex} of ${filteredCount} (filtered from ${totalCount})`

  return (
    <div
      className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-cf-border bg-cf-surface px-4 py-3"
      data-testid="list-pagination"
    >
      <span className="text-xs text-cf-ink-muted" data-testid="list-pagination-info">
        {showingLabel}
      </span>
      <Pagination
        page={clampedPage}
        setPage={setPage}
        perPage={pageSize}
        totalCount={filteredCount}
      >
        <Pagination.Controls />
      </Pagination>
    </div>
  )
}
