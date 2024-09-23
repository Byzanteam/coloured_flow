defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Object do
  @moduledoc """
  JSON instance Ecto type.

  This ceto type supports the following options:

  - `:codec` - the codec to use for encoding and decoding the JSON instance.
  """

  use Ecto.ParameterizedType

  @type t() :: map()

  @impl Ecto.ParameterizedType
  def type(_params), do: :map

  @impl Ecto.ParameterizedType
  def init(opts) do
    codec = Keyword.fetch!(opts, :codec)
    Enum.into(opts, %{codec: codec})
  end

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump

  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  def cast(data, %{codec: codec}) when is_map(data) do
    {:ok, codec.decode(data)}
  end

  def cast(_data, _params), do: :error

  @impl Ecto.ParameterizedType
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(data, _loader, %{codec: codec}) when is_map(data) do
    {:ok, codec.decode(data)}
  end

  def load(_data, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(nil, _loader, _params), do: {:ok, nil}

  def dump(data, _dumper, %{codec: codec}) when is_struct(data) do
    {:ok, codec.encode(data)}
  end

  def dump(_data, _dumper, _params), do: :error
end