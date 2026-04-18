# OTP 28 Dialyzer is stricter with opaque types. Ecto.Multi internally uses
# MapSet which wraps the opaque :sets.set(), triggering false positives.
# Tracked in: https://github.com/elixir-ecto/ecto/issues/4707
# Remove after upgrading to an Elixir version that fully fixes this.
[
  ~r/call_without_opaque.*opaque term/
]
