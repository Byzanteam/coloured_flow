defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.ObjectTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec
  alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Object

  defmodule MyStruct do
    @moduledoc false

    use TypedStructor

    typed_structor do
      field :foo, :string
    end
  end

  defmodule MyCodec do
    @moduledoc false
    use Codec

    @impl Codec
    def encode(%MyStruct{} = struct, _options) do
      %{"foo" => struct.foo}
    end

    @impl Codec
    def decode(%{"foo" => foo}, _options) do
      %MyStruct{foo: foo}
    end
  end

  @ecto_type Ecto.ParameterizedType.init(Object, codec: MyCodec)

  test "cast" do
    assert {:ok, %MyStruct{foo: "foo"}} ===
             Ecto.Type.cast(@ecto_type, %{"foo" => "foo", "bar" => "bar"})

    assert {:ok, nil} === Ecto.Type.cast(@ecto_type, nil)
    assert :error === Ecto.Type.cast(@ecto_type, "string")
  end

  test "load" do
    assert {:ok, %MyStruct{foo: "foo"}} === Ecto.Type.load(@ecto_type, %{"foo" => "foo"})
    assert {:ok, nil} === Ecto.Type.load(@ecto_type, nil)
    assert :error === Ecto.Type.load(@ecto_type, "string")
  end

  test "dump" do
    assert {:ok, %{"foo" => "foo"}} === Ecto.Type.dump(@ecto_type, %MyStruct{foo: "foo"})
    assert {:ok, nil} === Ecto.Type.dump(@ecto_type, nil)
    assert :error === Ecto.Type.dump(@ecto_type, "string")
  end
end
