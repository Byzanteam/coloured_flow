defmodule ColouredFlow.Runner.Storage.Schemas.Types do
  @moduledoc """
  This module defines the types used in the ColouredFlow.Runner.Storage.Schemas
  module.
  """

  @typedoc """
  The type for a primary_key or foreign_key, represented as a UUID.
  """
  @type id() :: Ecto.UUID.t()

  @typedoc """
  Represents an optional UUID, which can be `nil`.
  """
  @type maybe_id() :: ColouredFlow.Types.maybe(id())

  @typedoc """
  Represents an Ecto association, which can either be not loaded or of type `t`.
  """
  @type association(t) :: Ecto.Association.NotLoaded.t() | t

  @typedoc """
  Represents an optional Ecto association, which can either be not loaded, of type
  `t`, or `nil`.
  """
  @type maybe_association(t) :: Ecto.Association.NotLoaded.t() | ColouredFlow.Types.maybe(t)
end
