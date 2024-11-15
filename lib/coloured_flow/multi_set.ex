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

  @typep internal(value) :: %{value => pos_integer()}

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
  Checks if `value` is an empty `multi_set`.

  ## Examples

      iex> ColouredFlow.MultiSet.is_empty(ColouredFlow.MultiSet.new())
      true

      iex> ColouredFlow.MultiSet.is_empty(ColouredFlow.MultiSet.new(["a", "b", "c"]))
      false
  """
  defguard is_empty(value) when is_struct(value, __MODULE__) and map_size(value.map) === 0

  @doc """
  Get the coefficient of `value` in the `multi_set`.
  If the `value` is not in the `multi_set`, a `KeyError` is raised.
  This can be used in guards, similar to `ColouredFlow.MultiSet.coefficient/2`.
  """
  defmacro multi_set_coefficient(multi_set, value) do
    quote do
      :erlang.map_get(unquote(value), unquote(multi_set).map)
    end
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
  Pop `count` occurrences of `value` from the `multi_set`.

  Returns a tuple with the number of occurrences popped and the resulting `multi_set`.

  ## Examples

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      iex> {1, _multi_set} = ColouredFlow.MultiSet.pop(multi_set, "a")
      {1, ColouredFlow.MultiSet.from_pairs([{2, "a"}, {2, "b"}, {1, "c"}])}
      iex> {3, _multi_set} = ColouredFlow.MultiSet.pop(multi_set, "a", 3)
      {3, ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])}

      iex> multi_set = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      iex> {3, _multi_set} = ColouredFlow.MultiSet.pop(multi_set, "a", 100)
      {3, ColouredFlow.MultiSet.from_pairs([{2, "b"}, {1, "c"}])}
      iex> {0, _multi_set} = ColouredFlow.MultiSet.pop(multi_set, "d")
      {0, ColouredFlow.MultiSet.from_pairs([{3, "a"}, {2, "b"}, {1, "c"}])}
  """
  @spec pop(t(val), val, count) :: {count, t(val)} when count: non_neg_integer(), val: value()
  def pop(%__MODULE__{} = multi_set, value, count \\ 1) do
    case Map.pop(multi_set.map, value) do
      {nil, _map} ->
        {0, multi_set}

      {coefficient, map} when coefficient <= count ->
        {coefficient, %{multi_set | map: map}}

      {coefficient, map} when coefficient > count ->
        {count, %{multi_set | map: Map.put(map, value, coefficient - count)}}
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
  Returns the difference of two `multi_set`s.

  The difference is calculated by subtracting the coefficients of elements
  in `multi_set2` from the coefficients of elements in `multi_set1`. If an
  element in `multi_set2` is not present in `multi_set1`, it is ignored.
  If the resulting coefficient is zero or negative, the element is removed
  from the resulting `multi_set`.

  ## Examples

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["a", "b", "c", "a"])
      iex> ColouredFlow.MultiSet.difference(multi_set1, multi_set2)
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}])

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c"])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["d", "e", "f"])
      iex> ColouredFlow.MultiSet.difference(multi_set1, multi_set2)
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}, {1, "c"}])

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c"])
      iex> multi_set2 = ColouredFlow.MultiSet.new([])
      iex> ColouredFlow.MultiSet.difference(multi_set1, multi_set2)
      ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}, {1, "c"}])
  """
  @spec difference(t(), t()) :: t()
  def difference(%__MODULE__{} = multi_set1, %__MODULE__{map: map2}) when map_size(map2) === 0,
    do: multi_set1

  def difference(%__MODULE__{} = multi_set1, %__MODULE__{} = multi_set2) do
    map =
      Enum.reduce(multi_set1.map, %{}, fn {value, coefficient}, acc ->
        coefficient2 = Map.get(multi_set2.map, value, 0)

        case coefficient - coefficient2 do
          new_coefficient when new_coefficient > 0 ->
            Map.put(acc, value, new_coefficient)

          _other ->
            acc
        end
      end)

    %__MODULE__{map: map}
  end

  @doc """
  Returns the difference of two `multi_set`s.

  Behaves like `difference/2`, but returns `:error` if the `coefficient` of any `value`
  in `multi_set2` is greater than the `coefficient` of the same `value` in `multi_set1`,
  and if `multi_set2` contains a `value` that is not in `multi_set1`.
  That is to say, `multi_set2` must be included in `multi_set1`.

  ## Examples

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["a", "b", "c", "a"])
      iex> ColouredFlow.MultiSet.safe_difference(multi_set1, multi_set2)
      {:ok, ColouredFlow.MultiSet.from_pairs([{1, "a"}, {1, "b"}])}
      iex> ColouredFlow.MultiSet.safe_difference(multi_set2, multi_set1)
      :error

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c"])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["d", "e", "f"])
      iex> ColouredFlow.MultiSet.safe_difference(multi_set1, multi_set2)
      :error

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a"])
      iex> multi_set2 = ColouredFlow.MultiSet.new()
      iex> ColouredFlow.MultiSet.safe_difference(multi_set1, multi_set2)
      {:ok, ColouredFlow.MultiSet.from_pairs([{1, "a"}])}
      iex> ColouredFlow.MultiSet.safe_difference(multi_set2, multi_set1)
      :error
  """
  @spec safe_difference(t(), t()) :: {:ok, t()} | :error
  def safe_difference(%__MODULE__{} = multi_set1, %__MODULE__{map: map2})
      when map_size(map2) === 0,
      do: {:ok, multi_set1}

  def safe_difference(%__MODULE__{} = multi_set1, %__MODULE__{} = multi_set2) do
    multi_set1.map
    |> Enum.reduce_while(
      {%{}, multi_set2.map},
      fn {value, coefficient}, {map1, map2} ->
        {coefficient2, map2} = Map.pop(map2, value, 0)

        case coefficient - coefficient2 do
          0 ->
            {:cont, {map1, map2}}

          new_coefficient when new_coefficient > 0 ->
            {:cont, {Map.put(map1, value, new_coefficient), map2}}

          _other ->
            {:halt, :error}
        end
      end
    )
    |> case do
      :error -> :error
      {_map1, map2} when map_size(map2) > 0 -> :error
      {map1, _map2} -> {:ok, %__MODULE__{map: map1}}
    end
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
  Check if `multi_set2` is included in `multi_set1`.

  ## Examples

      iex> multi_set1 = ColouredFlow.MultiSet.new(["a", "b", "c", "a", "b", "a"])
      iex> multi_set2 = ColouredFlow.MultiSet.new(["a", "b", "c"])
      iex> ColouredFlow.MultiSet.include?(multi_set1, multi_set2)
      true
      iex> ColouredFlow.MultiSet.include?(multi_set2, multi_set1)
      false
      iex> multi_set3 = multi_set1
      iex> ColouredFlow.MultiSet.include?(multi_set1, multi_set3)
      true
      iex> ColouredFlow.MultiSet.include?(multi_set3, multi_set1)
      true

      iex> ColouredFlow.MultiSet.include?(ColouredFlow.MultiSet.new(), ColouredFlow.MultiSet.new())
      true
  """
  @spec include?(t(), t()) :: boolean()
  def include?(%__MODULE__{} = multi_set1, %__MODULE__{} = multi_set2) do
    Enum.all?(multi_set2.map, fn {value, coefficient} ->
      coefficient <= Map.get(multi_set1.map, value, 0)
    end)
  end

  @doc """
  Handles the sigil `~MS`(that is `multi_set`).

  It returns a `multi_set` split by whitespace.
  Character interpolation happens for each pairs.

  This sigil accepts pairs of the form `coefficient**value`,
  a literal `value`(the coefficient is 1),
  or a variable `value`(the coefficient is 1).

  ## Examples

      iex> a = :a
      iex> ~MS[3**(1+1) 2**a 1**"a"]
      ColouredFlow.MultiSet.from_pairs([{3, 2}, {2, :a}, {1, "a"}])
      iex> ~MS[a "a"]
      ColouredFlow.MultiSet.from_pairs([{1, :a}, {1, "a"}])
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec sigil_MS(term(), list(binary())) :: Macro.t()
  # credo:disable-for-next-line Credo.Check.Readability.FunctionNames
  defmacro sigil_MS({:<<>>, _meta, [pairs]} = _term, _modifiers) do
    {list, is_literal?} =
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
      |> Enum.map_reduce(true, fn {coefficient, value}, acc ->
        with true <- Macro.quoted_literal?(coefficient),
             true <- Macro.quoted_literal?(value),
             {coefficient, []} <- safe_eval(coefficient),
             {value, []} <- safe_eval(value) do
          {{coefficient, value}, acc}
        else
          _other ->
            {{quote(do: unquote(coefficient)), quote(do: unquote(value))}, false}
        end
      end)

    if is_literal? do
      quote do
        unquote(Macro.escape(from_pairs(list)))
      end
    else
      quote do
        unquote(__MODULE__).from_pairs([unquote_splicing(list)])
      end
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
            The sigils ~MS only accepts pairs of the form `coefficient**value`,
            a literal `value`(the coefficient is 1),
            or a variable `value`(the coefficient is 1).
            """,
            stacktrace
          )
        end
    end
  end

  defp safe_eval(expr) do
    Code.eval_quoted(expr, [])
  rescue
    _error -> :error
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
