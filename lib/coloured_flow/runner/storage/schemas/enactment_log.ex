defmodule ColouredFlow.Runner.Storage.Schemas.EnactmentLog do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())

    field :state, Enactment.state()

    field :termination, %{type: ColouredFlow.Termination.type(), message: String.t() | nil},
      enforce: false

    field :exception, %{type: String.t(), message: String.t(), original: String.t()},
      enforce: false

    field :inserted_at, NaiveDateTime.t()
  end

  schema "enactment_logs" do
    belongs_to :enactment, Enactment

    field :state, Ecto.Enum, values: Enactment.__states__()

    embeds_one :termination, Termination, primary_key: false, on_replace: :delete do
      @moduledoc false

      field :type, Ecto.Enum, values: ColouredFlow.Termination.__types__()
      field :message, :string
    end

    embeds_one :exception, Exception, primary_key: false, on_replace: :delete do
      @moduledoc false

      field :type, :string
      field :message, :string
      field :original, :string
    end

    timestamps(updated_at: false)
  end
end
