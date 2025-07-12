locals_without_parens = [colset: 1, var: 1, val: 1, return: 1]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:typed_structor, :ecto, :ecto_sql],
  locals_without_parens: locals_without_parens,
  plugins: [DprintMarkdownFormatter],
  export: [
    locals_without_parens: locals_without_parens
  ]
]
