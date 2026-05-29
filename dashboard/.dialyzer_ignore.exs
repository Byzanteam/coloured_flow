# Phoenix.Router's generated dispatch code triggers a benign pattern_match
# warning under Erlang/OTP 28 + Elixir 1.19 dialyzer. The warning is upstream
# (deps/phoenix/lib/phoenix/router.ex) and unfixable from this app.
[
  ~r/deps\/phoenix\/lib\/phoenix\/router\.ex.*pattern_match/
]
