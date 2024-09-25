defmodule ColouredFlow.Runner.Storage.Repo do
  @moduledoc false

  @repo_functions [
    all: 1,
    get!: 2,
    get_by: 2,
    insert!: 2,
    insert_all: 3,
    one!: 1,
    transaction: 1,
    update_all: 2
  ]

  for {fun, arity} <- @repo_functions do
    args = Macro.generate_arguments(arity, __MODULE__)

    @doc """
    Delegate to `c:Ecto.Repo.#{fun}/#{arity}`.
    """
    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(fun)(unquote_splicing(args)) do
      __dispatch__(unquote(fun), unquote(args))
    end
  end

  defp __dispatch__(fun, args) do
    repo = Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)[:repo]

    apply(repo, fun, args)
  end
end
