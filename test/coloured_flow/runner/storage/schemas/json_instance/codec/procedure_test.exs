defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ProcedureTest do
  use ColouredFlow.Runner.CodecCase, codec: Procedure, async: true

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Procedure

  describe "codec" do
    test "works" do
      procedures = [
        %Procedure{
          name: :add,
          expression: Expression.build!("x + y"),
          result: {:integer, []}
        },
        %Procedure{
          name: :sub,
          expression: Expression.build!("x - y"),
          result: {:boolean, []}
        }
      ]

      assert_codec(procedures)
    end
  end
end
