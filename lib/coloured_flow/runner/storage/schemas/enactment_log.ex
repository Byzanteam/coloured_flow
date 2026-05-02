defmodule ColouredFlow.Runner.Storage.Schemas.EnactmentLog do
  @moduledoc """
  The schema for the enactment log in the coloured_flow runner.

  Each row is one lifecycle event. The `state` column captures whether the
  enactment is `:running`, `:terminated`, or `:exception` after the event. The
  `:running` state is reused for non-fatal records like snapshot self-heal and
  crash markers consumed by the consecutive-crash circuit breaker.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  typed_schema "enactment_logs", null: false do
    belongs_to :enactment, Enactment

    field :state, Ecto.Enum, values: Enactment.__states__(), typed: [type: Enactment.state()]

    embeds_one :termination, Termination,
      primary_key: false,
      on_replace: :delete,
      typed: [null: true] do
      @moduledoc false

      field :type, Ecto.Enum,
        values: ColouredFlow.Runner.Termination.__types__(),
        typed: [type: ColouredFlow.Runner.Termination.type()]

      field :message, :string, typed: [null: true]
    end

    embeds_one :exception, Exception,
      primary_key: false,
      on_replace: :delete,
      typed: [null: true] do
      @moduledoc false

      field :reason, Ecto.Enum,
        values: ColouredFlow.Runner.Exception.__reasons__(),
        typed: [type: ColouredFlow.Runner.Exception.reason()]

      field :type, :string
      field :message, :string
      field :original, :string
    end

    timestamps(updated_at: false)
  end

  @spec build_running(Enactment.t()) :: Ecto.Changeset.t(t())
  def build_running(enactment) do
    Ecto.Changeset.change(%__MODULE__{enactment_id: enactment.id}, state: :running)
  end

  @spec build_termination(
          Enactment.t(),
          ColouredFlow.Runner.Termination.type(),
          options :: [message: String.t()]
        ) :: Ecto.Changeset.t(t())
  def build_termination(enactment, type, options) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(state: :terminated)
    |> Ecto.Changeset.put_embed(:termination, %__MODULE__.Termination{
      type: type,
      message: Keyword.get(options, :message)
    })
  end

  @spec build_exception(Enactment.t(), ColouredFlow.Runner.Exception.reason(), Exception.t()) ::
          Ecto.Changeset.t(t())
  def build_exception(enactment, reason, exception) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(state: :exception)
    |> put_exception_embed(reason, exception)
  end

  @doc """
  Build a non-fatal log row that records an exceptional event without changing the
  enactment state. Used for `:snapshot_corrupt` self-heals and `:crash` markers
  consumed by the consecutive-crash circuit breaker.
  """
  @spec build_recovery(Enactment.t(), ColouredFlow.Runner.Exception.reason(), Exception.t()) ::
          Ecto.Changeset.t(t())
  def build_recovery(enactment, reason, exception) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(state: :running)
    |> put_exception_embed(reason, exception)
  end

  defp put_exception_embed(changeset, reason, exception) do
    Ecto.Changeset.put_embed(changeset, :exception, %__MODULE__.Exception{
      reason: reason,
      type: inspect(exception.__struct__),
      message: Exception.message(exception),
      original: inspect(exception)
    })
  end
end
