defmodule ColouredFlowDashboard.ElixirTermDecoderTest do
  use ExUnit.Case, async: true

  alias ColouredFlowDashboard.ElixirTermDecoder

  # Pin atoms used by literal tests onto the BEAM so
  # `Code.string_to_quoted(_, existing_atoms_only: true)` accepts them.
  _atom_pins = [:approve, :tool_read, :user, :running, :reject]

  describe "decode/1 — literals accepted" do
    test "atom literal" do
      assert {:ok, :approve} = ElixirTermDecoder.decode(":approve")
      assert {:ok, true} = ElixirTermDecoder.decode("true")
      assert {:ok, nil} = ElixirTermDecoder.decode("nil")
    end

    test "integer / float / binary literals" do
      assert {:ok, 42} = ElixirTermDecoder.decode("42")
      assert {:ok, -1} = ElixirTermDecoder.decode("-1")
      assert {:ok, 1.5} = ElixirTermDecoder.decode("1.5")
      assert {:ok, "hello"} = ElixirTermDecoder.decode(~s|"hello"|)
    end

    test "2-tuple and n-tuple literals" do
      assert {:ok, {:tool_read, "path"}} =
               ElixirTermDecoder.decode(~s|{:tool_read, "path"}|)

      assert {:ok, {1, 2, 3}} = ElixirTermDecoder.decode("{1, 2, 3}")
    end

    test "list literal" do
      assert {:ok, [1, 2, 3]} = ElixirTermDecoder.decode("[1, 2, 3]")
      assert {:ok, []} = ElixirTermDecoder.decode("[]")
    end

    test "keyword list literal" do
      assert {:ok, [user: "hi"]} = ElixirTermDecoder.decode(~s|[user: "hi"]|)

      assert {:ok, [user: "u", running: true]} =
               ElixirTermDecoder.decode(~s|[user: "u", running: true]|)
    end

    test "leading / trailing whitespace tolerated" do
      assert {:ok, :approve} = ElixirTermDecoder.decode("  :approve\n")
    end
  end

  describe "decode/1 — rejected" do
    test "function call rejected" do
      assert {:error, {:invalid_elixir, reason}} =
               ElixirTermDecoder.decode(~s|IO.puts("x")|)

      assert is_binary(reason)
    end

    test "bare variable reference rejected" do
      assert {:error, {:invalid_elixir, reason}} = ElixirTermDecoder.decode("x")
      assert reason =~ "calls and variables"
    end

    test "module-qualified call rejected" do
      assert {:error, {:invalid_elixir, _reason}} =
               ElixirTermDecoder.decode("Kernel.+(1, 2)")
    end

    test "syntactically broken input surfaces parser message" do
      assert {:error, {:invalid_elixir, _reason}} =
               ElixirTermDecoder.decode("{not closed")
    end

    test "empty string rejected" do
      assert {:error, {:invalid_elixir, "value is empty"}} = ElixirTermDecoder.decode("")
      assert {:error, {:invalid_elixir, "value is empty"}} = ElixirTermDecoder.decode("   \n")
    end

    test "unknown atoms rejected via existing_atoms_only" do
      # The atom name below is built at runtime so it never enters the
      # compile-time atom table; the parser rejects it as a syntax-level
      # error.
      payload = ":cf_dashboard_decoder_test_atom_#{System.unique_integer([:positive])}"
      assert {:error, {:invalid_elixir, _reason}} = ElixirTermDecoder.decode(payload)
    end
  end
end
