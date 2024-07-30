defmodule ColouredFlow.MultiSet do
  @moduledoc """
  A [`multi_set`](https://en.wikipedia.org/wiki/Multiset)(aka `bag`) is a set that allows multiple occurrences of its elements.

  A `multi_set` can be constructed using `new/0` or `new/1` functions:

      iex> ColouredFlow.MultiSet.new()
      ColouredFlow.MultiSet.from_pairs([])

      iex> ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
  """

  use TypedStructor

  @opaque internal(value) :: %{value => pos_integer()}

  @type coefficient() :: non_neg_integer()
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type value() :: term()

  @type pair() :: {coefficient(), value()}

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type t() :: t(term())

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    parameter :value

    field :map, internal(value), default: %{}
  end

  @doc """
  Returns a new `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new()
      ColouredFlow.MultiSet.from_pairs([])
      iex> ColouredFlow.MultiSet.new(multi_set)
      ColouredFlow.MultiSet.from_pairs([])
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a `multi_set` from an enumerable

  ## Examples

      iex> ColouredFlow.MultiSet.new(["a", "b", "c"])
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
  """
  @spec new(Enumerable.t()) :: t()
  def new(enumerable)
  def new(%__MODULE__{} = multi_set), do: multi_set

  def new(enumerable) do
    map = Enum.frequencies(enumerable)

    %__MODULE__{map: map}
  end

  @doc """
  Creates a `multi_set` from a list of `{coefficient, value}` pairs.

  ## Examples

      iex> ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}, {0, "d"}])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])

      iex> ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "a"}, {1, "a"}])
      ColouredFlow.MultiSet.from_pairs([{6, "a"}])
  """
  @spec from_pairs([pair()]) :: t()
  def from_pairs(list) when is_list(list) do
    map =
      list
      |> Enum.filter(&(elem(&1, 0) > 0))
      |> Enum.reduce(%{}, fn {coefficient, value}, acc ->
        Map.update(acc, value, coefficient, &(&1 + coefficient))
      end)
      |> Map.new()

    %__MODULE__{map: map}
  end

  @doc """
  Returns pairs list of the `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.to_pairs(multi_set)
      [{3, "a"}, {2, "b"}, {1, "c"}]
  """
  @spec to_pairs(t()) :: [pair()]
  def to_pairs(%__MODULE__{} = multi_set) do
    Enum.map(multi_set.map, fn {value, coefficient} ->
      {coefficient, value}
    end)
  end

  @doc """
  Duplicates a value `coefficient` times.

  ## Examples

      iex> ColouredFlow.MultiSet.duplicate("a", 3)
      ColouredFlow.MultiSet.from_pairs([{3, "a"}])

      iex> ColouredFlow.MultiSet.duplicate("a", 0)
      ColouredFlow.MultiSet.from_pairs([])
  """
  @spec duplicate(value(), coefficient()) :: t()
  def duplicate(_value, 0) do
    new()
  end

  def duplicate(value, coefficient) when coefficient > 0 do
    %__MODULE__{map: %{value => coefficient}}
  end

  @doc """
  Returns the elements of the `multi_set` as a list.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.to_list(multi_set)
      ["a", "a", "a", "b", "b", "c"]
  """
  @spec to_list(t()) :: Enumerable.t()
  def to_list(%__MODULE__{} = multi_set) do
    Enum.flat_map(multi_set.map, fn {value, coefficient} ->
      List.duplicate(value, coefficient)
    end)
  end

  @doc """
  Returns the number of elements in the `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.size(multi_set)
      6
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = multi_set) do
    Enum.reduce(multi_set.map, 0, fn {_value, coefficient}, acc ->
      coefficient + acc
    end)
  end

  @doc """
  Inserts `value` into the `multi_set`. If `value` is already in the `multi_set`, its
  `coefficient` is incremented by 1.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new()
      ColouredFlow.MultiSet.from_pairs([])
      iex> multi_set = ColouredFlow.MultiSet.put(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{1, "a"}])
      iex> ColouredFlow.MultiSet.put(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{2, "a"}])
  """
  @spec put(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put(%__MODULE__{} = multi_set, value) do
    %{multi_set | map: Map.update(multi_set.map, value, 1, &(&1 + 1))}
  end

  @doc """
  Deletes `value` from the `multi_set`. If the `coefficient` of `value` is greater than 1,
  it is decremented by 1.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> multi_set = ColouredFlow.MultiSet.delete(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{2, "a"}, {2, "b"}, {1, "c"}])
      iex> multi_set = ColouredFlow.MultiSet.delete(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {2, "b"}, {1, "c"}])
      iex> multi_set = ColouredFlow.MultiSet.delete(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.delete(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])
  """
  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{} = multi_set, value) do
    case Map.pop(multi_set.map, value) do
      {nil, _map} -> multi_set
      {1, map} -> %{multi_set | map: map}
      {coefficient, map} -> %{multi_set | map: Map.put(map, value, coefficient - 1)}
    end
  end

  @doc """
  Drops `value` from the `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> multi_set = ColouredFlow.MultiSet.drop(multi_set, "a")
      ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.drop(multi_set, "d")
      ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])
  """
  @spec drop(t(val), val) :: t(val) when val: value()
  def drop(%__MODULE__{} = multi_set, value) do
    %{multi_set | map: Map.delete(multi_set.map, value)}
  end

  @doc """
  Checks if `multi_set` contains `value`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.member?(multi_set, "a")
      true
      iex> ColouredFlow.MultiSet.member?(multi_set, "d")
      false
  """
  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{} = multi_set, value) do
    Map.has_key?(multi_set.map, value)
  end

  @doc """
  Returns the `coefficient` of `value` in the `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> ColouredFlow.MultiSet.coefficient(multi_set, "a")
      3
      iex> ColouredFlow.MultiSet.coefficient(multi_set, "b")
      2
      iex> ColouredFlow.MultiSet.coefficient(multi_set, "c")
      1
      iex> ColouredFlow.MultiSet.coefficient(multi_set, "d")
      0
  """
  @spec coefficient(t(), value()) :: coefficient()
  def coefficient(%__MODULE__{} = multi_set, value) do
    Map.get(multi_set.map, value, 0)
  end

  @doc """
  Returns the `multi_set` that is the union of `multi_set1` and `multi_set2`.

  ## Examples

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["a", "b", "c", "d", "e", "f"])
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}, {1, "c"}, {1, "d"}, {1, "e"}, {1, "f"}])
      iex> ColouredFlow.MultiSet.union(multi_set1, multi_set2)
      ColouredFlow.MultiSet.from_pairs([{4, "a"}, {3, "b"}, {2, "c"}, {1, "d"}, {1, "e"}, {1, "f"}])
  """
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{} = multi_set1, %__MODULE__{} = multi_set2) do
    map =
      Enum.reduce(multi_set2.map, multi_set1.map, fn {value, coefficient}, acc ->
        Map.update(acc, value, coefficient, &(&1 + coefficient))
      end)

    %__MODULE__{map: map}
  end

  @doc """
  Handles the sigil `~b`(short for `bag`, aka `multi_set`).

  It returns a `multi_set` split by whitespace.
  Character interpolation happens for each pairs.

  This sigil accepts pairs of the form `coefficient**value`,
  a literal `value`(the coefficient is 1),
  or a variable `value`(the coefficient is 1).

  ## Examples

      iex> a = :a
      iex> ~b[3**(1+1) 2**a 1**"a"]
      ColouredFlow.MultiSet.from_pairs([{3, 2}, {2, :a}, {1, "a"}])
      iex> ~b[a "a"]
      ColouredFlow.MultiSet.from_pairs([{1, :a}, {1, "a"}])
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec sigil_b(term(), list(binary())) :: Macro.t()
  defmacro sigil_b(term, modifiers)

  defmacro sigil_b({:<<>>, _meta, [pairs]}, _modifiers) do
    list =
      pairs
      |> String.split()
      |> Enum.map_reduce(1, fn pair, column ->
        quoted =
          Code.string_to_quoted!(pair,
            file: __CALLER__.file,
            line: __CALLER__.line,
            column: column
          )

        {extract_pair(quoted, __CALLER__), column + String.length(pair)}
      end)
      |> elem(0)
      |> Enum.map(fn {coefficient, value} ->
        {quote(do: unquote(coefficient)), quote(do: unquote(value))}
      end)

    quote do
      unquote(__MODULE__).from_pairs([unquote_splicing(list)])
    end
  end

  defp extract_pair(quoted, caller) do
    case quoted do
      {:**, _meta, [coefficient, value]} ->
        {coefficient, value}

      {_function_name, _meta, nil} ->
        {1, quoted}

      _other ->
        if Macro.quoted_literal?(quoted) do
          {1, quoted}
        else
          stacktrace = Macro.Env.stacktrace(caller)

          reraise(
            """
            The sigils ~b only accepts pairs of the form `coefficient**value`,
            a literal `value`(the coefficient is 1),
            or a variable `value`(the coefficient is 1).
            """,
            stacktrace
          )
        end
    end
  end

  defimpl Enumerable do
    @moduledoc false

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def count(multi_set) do
      {:ok, @for.size(multi_set)}
    end

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def member?(multi_set, val) do
      {:ok, @for.member?(multi_set, val)}
    end

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def slice(multi_set) do
      size = @for.size(multi_set)
      {:ok, size, &@for.to_list/1}
    end

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def reduce(multi_set, acc, fun) do
      Enumerable.List.reduce(@for.to_list(multi_set), acc, fun)
    end
  end

  defimpl Collectable do
    @moduledoc false

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def into(%@for{} = map_set) do
      fun = fn
        set, {:cont, x} -> @for.put(set, x)
        set, :done -> set
        _set, :halt -> :ok
      end

      {map_set, fun}
    end
  end

  defimpl Inspect do
    @moduledoc false

    import Inspect.Algebra

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def inspect(multi_set, opts) do
      pairs = @for.to_pairs(multi_set)

      concat(["#{inspect(@for)}.from_pairs(", Inspect.List.inspect(pairs, opts), ")"])
    end
  end
end
