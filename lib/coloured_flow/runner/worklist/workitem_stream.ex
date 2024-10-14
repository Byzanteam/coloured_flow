defmodule ColouredFlow.Runner.Worklist.WorkitemStream do
  @moduledoc """
  The workitem stream in the coloured_flow runner.
  """

  alias ColouredFlow.Runner.Enactment.Workitem

  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  import Ecto.Query

  @type cursor_binary() :: binary()
  @type limit() :: non_neg_integer()
  @type list_option() :: {:after_cursor, cursor_binary()} | {:limit, limit()}
  @type list_options() :: [list_option()]

  @typep cursor() :: %{updated_at: NaiveDateTime.t(), id: Schemas.Types.id()}

  @default_limit 100

  @doc """
  Constructs a query to list the live workitems.
  """
  @spec live_query(list_options()) :: Ecto.Query.t()
  def live_query(options) do
    options = Keyword.validate!(options, [:after_cursor, :limit])
    limit = Keyword.get(options, :limit, @default_limit)
    after_cursor = options |> Keyword.get(:after_cursor) |> decode_cursor()

    Schemas.Workitem
    |> where([w], w.state in ^Workitem.__live_states__())
    |> filter_by_cursor(after_cursor)
    |> order_by(asc: :updated_at, asc: :id)
    |> limit(^limit)
  end

  @doc """
  Lists the live workitems.

  ## Options

  * `:after_cursor` - The cursor to start listing workitems from.
  * `:limit` - The maximum number of workitems to list.
  """
  @spec list_live(list_options()) :: {[Workitem.t()], cursor} | :end_of_stream
  def list_live(options \\ []) do
    options
    |> live_query()
    |> Repo.all()
    |> then(fn
      [] ->
        :end_of_stream

      workitems ->
        cursor = encode_cursor(workitems |> List.last() |> Map.take([:updated_at, :id]))
        workitems = Enum.map(workitems, &Schemas.Workitem.to_workitem/1)

        {workitems, cursor}
    end)
  end

  @spec encode_cursor(cursor_binary() | nil) :: cursor() | nil
  defp decode_cursor(nil), do: nil

  defp decode_cursor(cursor) when is_binary(cursor) do
    %{updated_at: updated_at, id: id} = :erlang.binary_to_term(cursor, [:safe])

    true = is_struct(updated_at, NaiveDateTime)
    id = Ecto.UUID.cast!(id)

    %{updated_at: updated_at, id: id}
  rescue
    e ->
      require Logger
      Logger.warning("Failed to decode cursor due to: #{inspect(e)}")

      nil
  end

  @spec encode_cursor(cursor()) :: cursor_binary()
  defp encode_cursor(%{updated_at: updated_at, id: id}),
    do: :erlang.term_to_binary(%{updated_at: updated_at, id: id})

  @spec filter_by_cursor(Ecto.Query.t(), cursor() | nil) :: Ecto.Query.t()
  defp filter_by_cursor(query, nil), do: query

  defp filter_by_cursor(query, cursor) do
    updated_at = Map.fetch!(cursor, :updated_at)
    id = Map.fetch!(cursor, :id)

    where(query, [w], (w.updated_at >= ^updated_at and w.id > ^id) or w.updated_at > ^updated_at)
  end
end
