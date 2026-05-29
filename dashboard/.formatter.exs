[
  import_deps: [:coloured_flow, :ecto, :ecto_sql, :phoenix, :typed_structor],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"],
  # Musubi 0.6 hex package does not ship `.formatter.exs`, so its DSL macros
  # would round-trip with parens added by `mix format`. Mirror the upstream
  # `:locals_without_parens` set inline.
  locals_without_parens: [
    attr: 2,
    attr: 3,
    command: 1,
    command: 2,
    field: 2,
    field: 3,
    payload: 2,
    payload: 3,
    state: 1,
    stream: 2,
    stream: 3,
    stream_async: 2,
    stream_async: 3
  ]
]
