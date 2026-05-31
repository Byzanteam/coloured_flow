import { useCallback, useMemo } from "react"
import { useSearchParams } from "react-router-dom"

const DEFAULT_PAGE_SIZE = 25
const VALID_PAGE_SIZES = new Set([10, 25, 50, 100])

export interface ListSearchParamsApi {
  /** Search query (trimmed empty -> ""). */
  q: string
  /** 1-indexed page. */
  page: number
  /** Items per page (clamped to valid set). */
  pageSize: number
  /** Read a raw param. */
  read(key: string): string | null
  /** Read a comma-separated multi-value param. */
  readList(key: string): string[]
  /** Set a single string param. Null/empty clears the key. */
  setParam(key: string, value: string | null): void
  /** Set a multi-value param. Empty array clears the key. */
  setList(key: string, values: readonly string[]): void
  /** Convenience setters. */
  setQ(next: string): void
  setPage(next: number): void
  setPageSize(next: number): void
  /** Clear every key in the provided list. */
  clear(keys: readonly string[]): void
}

const PAGE_KEY = "page"
const PAGE_SIZE_KEY = "pageSize"
const Q_KEY = "q"

/**
 * URL-backed list state. Search, page, page size, and arbitrary string /
 * multi-value filter params all live in the search string so a copy-pasted URL
 * fully restores the view. Stripping a key removes it from the URL.
 */
export function useListSearchParams(
  defaultPageSize: number = DEFAULT_PAGE_SIZE
): ListSearchParamsApi {
  const [params, setParams] = useSearchParams()

  const q = params.get(Q_KEY) ?? ""

  const pageRaw = Number(params.get(PAGE_KEY) ?? "1")
  const page = Number.isFinite(pageRaw) && pageRaw >= 1 ? Math.floor(pageRaw) : 1

  const pageSizeRaw = Number(params.get(PAGE_SIZE_KEY) ?? defaultPageSize)
  const pageSize = VALID_PAGE_SIZES.has(pageSizeRaw) ? pageSizeRaw : defaultPageSize

  const mutate = useCallback(
    (build: (next: URLSearchParams) => void) => {
      setParams(
        (prev) => {
          const next = new URLSearchParams(prev)
          build(next)
          return next
        },
        { replace: true }
      )
    },
    [setParams]
  )

  return useMemo<ListSearchParamsApi>(() => {
    return {
      q,
      page,
      pageSize,
      read(key) {
        return params.get(key)
      },
      readList(key) {
        const raw = params.get(key)
        if (!raw) return []
        return raw.split(",").filter((v) => v.length > 0)
      },
      setParam(key, value) {
        mutate((next) => {
          if (value === null || value === "") next.delete(key)
          else next.set(key, value)
          if (key !== PAGE_KEY) next.delete(PAGE_KEY)
        })
      },
      setList(key, values) {
        mutate((next) => {
          if (values.length === 0) next.delete(key)
          else next.set(key, values.join(","))
          next.delete(PAGE_KEY)
        })
      },
      setQ(value) {
        mutate((next) => {
          if (value === "") next.delete(Q_KEY)
          else next.set(Q_KEY, value)
          next.delete(PAGE_KEY)
        })
      },
      setPage(value) {
        mutate((next) => {
          if (value <= 1) next.delete(PAGE_KEY)
          else next.set(PAGE_KEY, String(value))
        })
      },
      setPageSize(value) {
        mutate((next) => {
          if (value === defaultPageSize) next.delete(PAGE_SIZE_KEY)
          else next.set(PAGE_SIZE_KEY, String(value))
          next.delete(PAGE_KEY)
        })
      },
      clear(keys) {
        mutate((next) => {
          for (const key of keys) next.delete(key)
          next.delete(PAGE_KEY)
        })
      }
    }
  }, [params, q, page, pageSize, defaultPageSize, mutate])
}

export const LIST_PAGE_SIZE_OPTIONS = [10, 25, 50, 100] as const
export const DEFAULT_LIST_PAGE_SIZE = DEFAULT_PAGE_SIZE
