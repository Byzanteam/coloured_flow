defmodule ColouredFlow.Runner.Storage.Schemas.EnactmentLog do
  @moduledoc """
  The schema for the enactment log in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())

    field :state, Enactment.state()

    field :termination,
          %{type: ColouredFlow.Runner.Termination.type(), message: String.t() | nil},
          enforce: false

    field :exception, %{type: String.t(), message: String.t(), original: String.t()},
      enforce: false

    field :inserted_at, DateTime.t()
  end

  schema "enactment_logs" do
    belongs_to :enactment, Enactment

    field :state, Ecto.Enum, values: Enactment.__states__()

    embeds_one :termination, Termination, primary_key: false, on_replace: :delete do
      @moduledoc false

      field :type, Ecto.Enum, values: ColouredFlow.Runner.Termination.__types__()
      field :message, :string
    end

    embeds_one :exception, Exception, primary_key: false, on_replace: :delete do
      @moduledoc false

      field :reason, Ecto.Enum, values: ColouredFlow.Runner.Exception.__reasons__()
      field :type, :string
      field :message, :string
      field :original, :string
    end

    timestamps(updated_at: false)
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
    |> Ecto.Changeset.put_embed(:exception, %__MODULE__.Exception{
      reason: reason,
      type: inspect(exception.__struct__),
      message: Exception.message(exception),
      original: inspect(exception)
    })
  end
end
