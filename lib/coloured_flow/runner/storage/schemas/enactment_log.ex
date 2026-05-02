defmodule ColouredFlow.Runner.Storage.Schemas.EnactmentLog do
  @moduledoc """
  The schema for the enactment log in the coloured_flow runner.

  Each row is one lifecycle event. The `kind` column captures what happened:

  | kind          | embed         | description                                      |
  | ------------- | ------------- | ------------------------------------------------ |
  | `:started`    | (none)        | Written on enactment insert.                     |
  | `:exception`  | `exception`   | An exceptional event occurred (any reason).      |
  | `:terminated` | `termination` | The enactment terminated (`:implicit             |
  | `:retried`    | `retry`       | The user reoffered an exception-state enactment. |

  Writing a `:exception` log row does not flip `enactments.state`. The state
  column flips only on insert (`:running`), `ensure_runnable/1` trip
  (`:exception`), `retry_enactment/2` (`:running`), and `terminate_enactment/4`
  (`:terminated`).
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  @kinds [:started, :exception, :terminated, :retried]

  typed_schema "enactment_logs", null: false do
    belongs_to :enactment, Enactment

    field :kind, Ecto.Enum,
      values: @kinds,
      typed: [type: :started | :exception | :terminated | :retried]

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

    embeds_one :retry, Retry, primary_key: false, on_replace: :delete, typed: [null: true] do
      @moduledoc false

      field :message, :string, typed: [null: true]
    end

    timestamps(updated_at: false)
  end

  @spec build_started(Enactment.t()) :: Ecto.Changeset.t(t())
  def build_started(enactment) do
    Ecto.Changeset.change(%__MODULE__{enactment_id: enactment.id}, kind: :started)
  end

  @spec build_termination(
          Enactment.t(),
          ColouredFlow.Runner.Termination.type(),
          options :: [message: String.t()]
        ) :: Ecto.Changeset.t(t())
  def build_termination(enactment, type, options) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(kind: :terminated)
    |> Ecto.Changeset.put_embed(:termination, %__MODULE__.Termination{
      type: type,
      message: Keyword.get(options, :message)
    })
  end

  @spec build_exception(Enactment.t(), ColouredFlow.Runner.Exception.reason(), Exception.t()) ::
          Ecto.Changeset.t(t())
  def build_exception(enactment, reason, exception) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(kind: :exception)
    |> Ecto.Changeset.put_embed(:exception, %__MODULE__.Exception{
      reason: reason,
      type: inspect(exception.__struct__),
      message: Exception.message(exception),
      original: inspect(exception)
    })
  end

  @spec build_retry(Enactment.t(), options :: [message: String.t()]) :: Ecto.Changeset.t(t())
  def build_retry(enactment, options) do
    %__MODULE__{enactment_id: enactment.id}
    |> Ecto.Changeset.change(kind: :retried)
    |> Ecto.Changeset.put_embed(:retry, %__MODULE__.Retry{
      message: Keyword.get(options, :message)
    })
  end
end
