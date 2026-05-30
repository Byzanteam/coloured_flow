# Phoenix.Router's generated dispatch code triggers a benign pattern_match
# warning under Erlang/OTP 28 + Elixir 1.19 dialyzer. The warning is upstream
# (deps/phoenix/lib/phoenix/router.ex) and unfixable from this app.
#
# Mix.* / Mix.Task.* references in our Mix tasks (cf.dashboard.reset_seed_db)
# resolve at task-runtime when Mix is loaded; the dialyzer PLT for this app
# only includes runtime deps so it cannot see them.
[
  ~r/deps\/phoenix\/lib\/phoenix\/router\.ex.*pattern_match/,
  ~r/lib\/mix\/tasks\/cf\.dashboard\.reset_seed_db\.ex.*(callback_info_missing|unknown_function)/
]
