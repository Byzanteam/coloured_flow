defmodule ColouredFlow.Runner.CodecCase do
  @moduledoc """
  This module is used to test the codec case.

  This test case do these things for you:

  1. Define a function `assert_codec/1` to test the codec
  2. Make an alias to the codec module as `Codec`

  This test case can be configured with the following options:

  - `codec`: the codec module to test, for example `ColourSet`, `Expression`, etc.
    This test case will expand its name to full qualified module name.
  """

  use ExUnit.CaseTemplate

  using opts do
    codec = get_codec(opts, __CALLER__)

    quote do
      alias unquote(codec), as: Codec

      defp assert_codec(list) do
        unquote(__MODULE__).assert_codec(unquote(codec), list)
      end
    end
  end

  defp get_codec(opts, caller) do
    codec = opts |> Keyword.fetch!(:codec) |> Macro.expand(caller)

    Module.safe_concat(ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec, codec)
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec assert_codec(module(), Keyword.t(), [term()]) :: :ok
  def assert_codec(codec, options \\ [], list) do
    Enum.each(list, fn colour_set ->
      json = codec.encode(colour_set, options)
      assert colour_set === codec.decode(json, options)
    end)
  end
end
