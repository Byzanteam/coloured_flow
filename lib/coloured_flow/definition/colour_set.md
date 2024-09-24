# Colour set

The colour set is like a data type in a programming language. We use Elixir
terms to define the colour sets.

## Unit colour sets

The unit colour set comprises a single element, denoted `{}`.

### Declaration Syntax

```elixir
colset name() :: {};
```

### Examples

```elixir
colset unit() :: {};
```

## Boolean colour sets

The Boolean values are `true` and `false`.

### Declaration syntax

```elixir
colset name() :: boolean();
```

### Examples

```elixir
colset bool() :: boolean();
```

## Integer colour sets

Integers are numerals without a decimal point.

### Declaration syntax

```elixir
colset name() :: integer();
```

### Examples

```elixir
colset int() :: integer();
```

### Operations

`i1 / i2` returns the floating-point division of `i1` by `i2`. If you want to
perform integer division, use the `Kernel.div/2` operator.

## Float(ing-point) colour sets

Floats are numerals with a decimal point. It follows IEEE 754 standard, except
for the `NaN` and `Infinity` values.

### Declaration syntax

```elixir
colset name() :: float();
```

### Examples

```elixir
colset real() :: float();
```

## String colour sets

Strings are UTF-8 encoded binaries.

### Declaration syntax

```elixir
colset name() :: binary();
```

### Examples

```elixir
colset string() :: bianry();
```

## Enumerated colour sets

Enumerated values are explicitly named as identifiers in the declaration.

### Declaration syntax

```elixir
colset name() :: id0 | id1 | ... | idn;
```

### Examples

```elixir
colset day() :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday;
```

## Tuple colour sets

A tuple is a compound data type with a fixed number of elements.

### Declaration syntax

```elixir
colset name() :: {colset1, colset2, ..., colsetn};

where n >= 2;
```

### Examples

```elixir
colset location() :: {float(), float()}
```

## Map colour sets

A map is a collection of key-value pairs.

### Declaration syntax

```elixir
colset name() :: %{key1: colset1(), key2: colset2(), ..., keyn: colsetn()};

where n >= 1;
```

### Examples

```elixir
colset user() :: %{name: binary(), age: integer()}
```

## Union colour sets

A union is a collection of different types of elements.

### Declaration syntax

```elixir
colset name() :: {name1, colset1()} | {name2, colset2()} | ... | {namen, colsetn()};

where n >= 2;
```

### Examples

```elixir
colset data()   :: binary()
colset ack()    :: integer()
colset packet() :: {:data, binary()} | {:ack, integer()}
```

## List colour sets

A list is a collection of elements, note that the elements must be of the same
type.

### Declaration syntax

```elixir
colset name() :: list(colset());
```

### Examples

```elixir
colset user()      :: %{name:  binary(), age: int()}
colset user_list() :: list(user())
```

## Examples of colour sets

```elixir
# primitive
colset unit()     :: {}
colset answer()   :: boolean();
colset int()      :: integer()
colset real()     :: float()
colset day()      :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday
colset weekend()  :: :saturday | :sunday

# tuple
colset location() :: {real(), real()}
# map
colset user()     :: %{name: binary(), age: int()}
# list
colset user_list():: list(user())

# union
colset data()     :: binary()
colset ack()      :: integer()
colset packet()   :: {:data, data()} | {:ack, ack()}

# variable
var p     :: user()
var users :: user_list()

# constant
val all_users   :: user_list() = [
  %{name: "Alice", age: 20},
  %{name: "Bob", age: 30}
]
val all_packets :: list(packet()) = [
  {:data, "Hello"},
  {:ack, 1}
]
```
