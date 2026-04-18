defmodule ColouredFlow.Runner.Storage.Schemas.Types do
  @moduledoc """
  This module defines the types used in the ColouredFlow.Runner.Storage.Schemas
  module.
  """

  @typedoc """
  The type for a primary_key or foreign_key, represented as a UUID.
  """
  @type id() :: Ecto.UUID.t()
end
