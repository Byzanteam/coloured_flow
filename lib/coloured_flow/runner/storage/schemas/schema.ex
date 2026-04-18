defmodule ColouredFlow.Runner.Storage.Schemas.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote generated: true do
      alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec
      alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Object

      use EctoTypedSchema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @schema_prefix "coloured_flow"
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
