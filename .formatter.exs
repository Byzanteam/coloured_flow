locals_without_parens = [
  colset: 1,
  var: 1,
  val: 1,
  return: 1,
  # ColouredFlow.DSL top-level
  name: 1,
  version: 1,
  # ColouredFlow.DSL.Place
  place: 2,
  initial_marking: 2,
  # ColouredFlow.DSL.Function
  function: 1,
  function: 2,
  # ColouredFlow.DSL.Transition
  transition: 2,
  guard: 1,
  action: 1,
  # ColouredFlow.DSL.Arc
  input: 2,
  input: 3,
  output: 2,
  output: 3,
  # ColouredFlow.DSL.Termination
  termination: 1,
  on_markings: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "*.md"],
  import_deps: [:typed_structor, :ecto, :ecto_sql],
  locals_without_parens: locals_without_parens,
  plugins: [DprintMarkdownFormatter],
  export: [
    locals_without_parens: locals_without_parens
  ]
]
