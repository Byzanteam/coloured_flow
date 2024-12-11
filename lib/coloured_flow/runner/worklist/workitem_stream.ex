defmodule ColouredFlow.Runner.Worklist.WorkitemStream do
  @moduledoc """
  The workitem stream in the coloured_flow runner.
  """

  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  import Ecto.Query

  @type cursor_binary() :: binary()
  @type limit() :: non_neg_integer()
  @type list_option() :: {:after_cursor, cursor_binary()} | {:limit, limit()}
  @type list_options() :: [list_option()]

  @typep cursor() :: %{updated_at: DateTime.t(), id: Schemas.Types.id()}

  @live_states ColouredFlow.Runner.Enactment.Workitem.__live_states__()
  @default_limit 100

  @doc """
  Constructs a query to list the live workitems.

  ## Options

  * `:after_cursor` - The cursor to start listing workitems from.
  * `:limit` - The maximum number of workitems to list.
  """
  @spec live_query(list_options()) :: Ecto.Query.t()
  def live_query(options \\ []) when is_list(options) do
    options = Keyword.validate!(options, [:after_cursor, limit: @default_limit])
    limit = Keyword.fetch!(options, :limit)
    after_cursor = options |> Keyword.get(:after_cursor) |> decode_cursor()

    Schemas.Workitem
    |> where([w], w.state in ^@live_states)
    |> filter_by_cursor(after_cursor)
    |> order_by(asc: :updated_at, asc: :id)
    |> limit(^limit)
  end

  @doc """
  Lists the live workitems.

  ## Examples

  ```elixir
  # build a stream to list live workitems
  Stream.resource(
    fn -> nil end,
    fn cursor ->
      [after_cursor: cursor]
      |> WorkitemStream.live_query()
      # filter by enactment_id if needed
      # |> where(enactment_id: ^enactment_id)
      |> WorkitemStream.list_live()
      |> case do
        :end_of_stream ->
          # simulate a delay for the next iteration
          Process.sleep(500)

          {[], cursor}

        {workitems, cursor} ->
          {workitems, cursor}
      end
    end,
    fn _cursor -> :ok end
  )
  ```
  """
  @spec list_live(Ecto.Queryable.t()) :: {[Schemas.Workitem.t()], cursor} | :end_of_stream
  def list_live(queryable) do
    queryable
    |> Repo.all()
    |> then(fn
      [] ->
        :end_of_stream

      workitems ->
        cursor = encode_cursor(workitems |> List.last() |> Map.take([:updated_at, :id]))

        {workitems, cursor}
    end)
  end

  @spec encode_cursor(cursor_binary() | nil) :: cursor() | nil
  defp decode_cursor(nil), do: nil

  defp decode_cursor(cursor) when is_binary(cursor) do
    %{updated_at: updated_at, id: id} = :erlang.binary_to_term(cursor, [:safe])

    true = is_struct(updated_at, DateTime)
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
