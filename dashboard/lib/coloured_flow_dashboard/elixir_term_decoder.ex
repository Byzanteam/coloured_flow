defmodule ColouredFlowDashboard.ElixirTermDecoder do
  @moduledoc """
  Parses an operator-supplied Elixir term literal into the corresponding
  Elixir term.

  Used by the outputs drawer for any colour set that does not map to a
  primitive control (`:string`, `:integer`, `:boolean`, `:enum`). The runner
  needs real Elixir values (atom-tagged tuples, lists, keyword lists), so the
  textarea ships an Elixir source fragment and this module parses it
  literally.

  Implementation rules:

    * Parsing goes through `Code.string_to_quoted/2` with `existing_atoms_only:
      true`. Atoms the operator types must already exist on the BEAM — true
      for atoms used in cpnet declarations and for any atom previously
      observed in another running flow.
    * `Code.eval_string/1` and friends are NOT called. The quoted AST is
      walked by an allow-list that only permits literal nodes: atoms,
      integers, floats, booleans, `nil`, binaries, tuples, lists, and
      keyword pairs spelled `[key: value]`.
    * Anything else (function calls, variable references, attribute lookups,
      sigils, captures, blocks, etc.) is rejected with
      `{:error, {:invalid_elixir, reason}}` where `reason` is a short,
      operator-facing string.
  """

  @typedoc "Reason payload surfaced as `:invalid_elixir` to the SPA."
  @type reason() :: binary()

  @doc """
  Decodes `text` into an Elixir term.

  Returns `{:ok, term}` on success, or `{:error, {:invalid_elixir, reason}}`
  when parsing fails or the AST contains a non-literal node.
  """
  @spec decode(binary()) :: {:ok, term()} | {:error, {:invalid_elixir, reason()}}
  def decode(text) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" do
      {:error, {:invalid_elixir, "value is empty"}}
    else
      case Code.string_to_quoted(trimmed, existing_atoms_only: true) do
        {:ok, ast} ->
          walk(ast)

        {:error, {_meta, message, token}} ->
          {:error, {:invalid_elixir, format_parse_error(message, token)}}
      end
    end
  end

  # Atom literals (covers `:foo`, `true`, `false`, `nil`).
  defp walk(atom) when is_atom(atom), do: {:ok, atom}
  defp walk(int) when is_integer(int), do: {:ok, int}
  defp walk(float) when is_float(float), do: {:ok, float}
  defp walk(bin) when is_binary(bin), do: {:ok, bin}

  # 2-tuples literal in Elixir AST: `{a, b}` quotes as a bare Elixir tuple.
  defp walk({left, right}) do
    with {:ok, l} <- walk(left),
         {:ok, r} <- walk(right) do
      {:ok, {l, r}}
    end
  end

  # N-tuples (`{a, b, c, ...}`) quote as `{:{}, meta, elements}`.
  defp walk({:{}, _meta, elements}) when is_list(elements) do
    case walk_list(elements) do
      {:ok, items} -> {:ok, List.to_tuple(items)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Unary `-` / `+` on numeric literals (`-1`, `+1.5`). The parser quotes
  # `-1` as `{:-, meta, [1]}`, so a strict literal walker has to special-case
  # it. Only the sign forms with one numeric child are allowed.
  defp walk({:-, _meta, [n]}) when is_integer(n) or is_float(n), do: {:ok, -n}
  defp walk({:+, _meta, [n]}) when is_integer(n) or is_float(n), do: {:ok, n}

  # Bare list. `[a: 1, b: 2]` quotes as `[a: 1, b: 2]` directly with
  # keyword-pair entries — those go through the 2-tuple clause above.
  defp walk(list) when is_list(list), do: walk_list(list)

  # Anything else is non-literal: function calls (`{:call, meta, args}`),
  # variables (`{:var, meta, ctx}` where ctx is atom), sigils, blocks, etc.
  defp walk({name, _meta, _args}) when is_atom(name) do
    {:error, {:invalid_elixir, "calls and variables are not allowed (`#{name}`)"}}
  end

  defp walk(other) do
    {:error, {:invalid_elixir, "unsupported literal: #{inspect(other)}"}}
  end

  defp walk_list(items) do
    result =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case walk(item) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          {:error, _reason} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _reason} = err -> err
    end
  end

  defp format_parse_error({prefix, suffix}, token)
       when is_binary(prefix) and is_binary(suffix) do
    format_parse_error("#{prefix}#{suffix}", token)
  end

  defp format_parse_error(message, token) when is_binary(message) and is_binary(token) do
    case String.trim(token) do
      "" -> message
      t -> "#{message}#{t}"
    end
  end

  defp format_parse_error(message, _other) when is_binary(message), do: message
  defp format_parse_error(_message, _token), do: "could not parse as Elixir term"
end
