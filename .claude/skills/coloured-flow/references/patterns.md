# Workflow patterns

Canonical patterns mined from the project's own test fixtures (`test/coloured_flow/dsl/cpnet_examples_test.exs`) and the `examples/traffic_light.livemd` walkthrough. Each one compiles. Adapt the colour sets, place/transition names, and guards to fit the problem; keep the structural shape.

## 1. Simple sequence

One transition moves a token from input to output unchanged.

**When**: a single observable step with shared state.

```elixir
defmodule SimpleSequence do
  use ColouredFlow.DSL

  colset int() :: integer()
  var x :: int()

  place :input, :int
  place :output, :int

  transition :pass_through do
    input :input, bind({1, x}), label: "in"
    output :output, {1, x}, label: "out"
  end
end
```

## 2. Parallel split

One transition produces tokens onto several downstream places, each consumed by an independent transition. The two `:pass_through_*` workitems run independently and concurrently.

**When**: a single event fans out into multiple independent follow-ups.

```elixir
defmodule ParallelSplit do
  use ColouredFlow.DSL

  colset int() :: integer()
  var x :: int()

  place :input, :int
  place :place_1, :int
  place :place_2, :int
  place :output_1, :int
  place :output_2, :int

  transition :parallel_split do
    input :input, bind({1, x})
    output :place_1, {1, x}
    output :place_2, {1, x}
  end

  transition :pass_through_1 do
    input :place_1, bind({1, x})
    output :output_1, {1, x}
  end

  transition :pass_through_2 do
    input :place_2, bind({1, x})
    output :output_2, {1, x}
  end
end
```

## 3. Deferred choice

Multiple transitions consume from the same input place. The first one to fire wins; the runner / external driver decides which. There is no built-in branch-selection logic — the *deferring* is the point.

**When**: an event has alternative responses and the choice is made by whoever drives the workitems (a user, a scheduler, an LLM acting on policy).

```elixir
defmodule DeferredChoice do
  use ColouredFlow.DSL

  colset int() :: integer()
  var x :: int()

  place :input, :int
  place :place, :int
  place :output_1, :int
  place :output_2, :int

  transition :pass_through do
    input :input, bind({1, x})
    output :place, {1, x}
  end

  transition :deferred_choice_1 do
    input :place, bind({1, x})
    output :output_1, {1, x}
  end

  transition :deferred_choice_2 do
    input :place, bind({1, x})
    output :output_2, {1, x}
  end
end
```

## 4. Generalised AND-join

A transition with multiple input places that all must contribute matching tokens before it can fire. The default (no extra constraint) requires *one token from each input*; share a variable across input arcs to require matching values.

**When**: multiple precondition streams must all be ready before the next step.

```elixir
defmodule GeneralizedAndJoin do
  use ColouredFlow.DSL

  colset int() :: integer()
  var x :: int()

  place :input1, :int
  place :input2, :int
  place :input3, :int
  place :output, :int

  transition :and_join do
    input :input1, bind({1, x}), label: "input1"
    input :input2, bind({1, x}), label: "input2"
    input :input3, bind({1, x}), label: "input3"

    output :output, {1, x}, label: "output"
  end
end
```

The shared `x` across all three input arcs forces *the same value* to appear on every input — that is what makes this a generalised AND-join rather than three independent consumers. Use distinct variables (`x`, `y`, `z`) to drop that constraint.

## 5. Thread merge (counted join)

A single transition that pulls *N copies* off one place. Use `bind({N, value})` on the input arc.

**When**: collecting N parallel results before continuing (counting semaphore, batch threshold).

```elixir
defmodule ThreadMerge do
  use ColouredFlow.DSL

  colset int() :: integer()
  var x :: int()

  place :input, :int
  place :merge, :int
  place :output, :int

  transition :branch_1 do
    input :input, bind({1, x})
    output :merge, {1, x}
  end

  transition :branch_2 do
    input :input, bind({1, x})
    output :merge, {1, x}
  end

  transition :thread_merge do
    input :merge, bind({2, 1})                   # require two copies of literal 1
    output :output, {1, 1}
  end
end
```

The literal value (`1`) in `bind({2, 1})` makes the merge insensitive to the actual values on `:merge`; replace with a variable to require *N copies of the same value*.

## 6. Transmission protocol with retries

Looped flow with conditional outputs (success / failure branches), an explicit acknowledgement channel, and stateful counters that survive across firings.

**When**: protocols, retry loops, idempotent re-delivery, anything where the same transition must keep firing until a condition holds.

```elixir
defmodule TransmissionProtocol do
  use ColouredFlow.DSL

  colset no()      :: integer()
  colset data()    :: binary()
  colset no_data() :: {integer(), binary()}
  colset bool()    :: boolean()

  var n :: no()
  var k :: no()
  var d :: data()
  var data :: data()
  var success :: bool()

  place :packets_to_send, :no_data
  place :a, :no_data
  place :b, :no_data
  place :data_recevied, :data
  place :next_rec, :no
  place :c, :no
  place :d, :no
  place :next_send, :no

  transition :send_packet do
    input :packets_to_send, bind({1, {n, d}})
    input :next_send, bind({1, {1, n}})

    output :packets_to_send, {1, {n, d}}         # keep packet (loop until acked)
    output :a, {1, {n, d}}
    output :next_send, {1, {1, n}}
  end

  transition :transmit_packet do
    input :a, bind({1, {n, d}})

    # `success` is a free variable in the output expression; the runner
    # treats it as nondeterministic and explores both branches.
    output :b, if(success, do: {1, {n, d}}, else: {0, {n, d}})
  end

  transition :receive_packet do
    input :b, bind({1, {n, d}})
    input :data_recevied, bind({1, data})
    input :next_rec, bind({1, k})

    output :data_recevied, if(n == k, do: {1, data <> d}, else: {1, data})
    output :c, if(n == k, do: {1, k + 1}, else: {1, k})
    output :next_rec, if(n == k, do: {1, k + 1}, else: {1, k})
  end

  transition :transmit_ack do
    input :c, bind({1, n})

    output :d, if(success, do: {1, n}, else: {0, n})
  end

  transition :receive_ack do
    input :next_send, bind({1, k})
    input :d, bind({1, n})

    output :next_send, {1, n}
  end
end
```

Key tricks:

- `output :packets_to_send, {1, {n, d}}` on `:send_packet` *re-deposits* the packet, so the sender keeps trying until acknowledgement bumps the sequence number.
- `output :p, if(cond, do: {1, …}, else: {0, …})` — multiplicity `0` means "produce nothing". This is the idiomatic conditional output.
- Sequence numbers (`n`, `k`) live in dedicated counter places (`:next_send`, `:next_rec`); transitions read-and-write them in one firing.

## 7. State machine with lifecycle drive

A finite-state machine where a single token (often the unit token `{}`) cycles through a fixed sequence of places, with side effects scheduled by `action` and the next firing kicked off by a lifecycle hook.

**When**: traffic lights, signalling protocols, recurring schedulers, anywhere the workflow itself is the supervisor of its own clock.

Reduced from `examples/traffic_light.livemd`:

```elixir
defmodule TrafficLight do
  use ColouredFlow.DSL, task_supervisor: TrafficLight.TaskSup

  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Storage

  name "TrafficLight"

  colset signal() :: {}
  var s :: signal()

  place :red_ew, :signal
  place :green_ew, :signal
  place :yellow_ew, :signal
  place :red_ns, :signal
  place :green_ns, :signal
  place :yellow_ns, :signal
  place :safe_ew, :signal
  place :safe_ns, :signal

  initial_marking :red_ew, ~MS[{}]
  initial_marking :red_ns, ~MS[{}]
  initial_marking :safe_ew, ~MS[{}]

  transition :turn_green_ew do
    input :red_ew, bind({1, s})
    input :safe_ew, bind({1, s})
    output :green_ew, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      :timer.sleep(10_000)
      TrafficLight.drive_next(event.enactment_id, "turn_yellow_ew")
    end
  end

  transition :turn_yellow_ew do
    input :green_ew, bind({1, s})
    output :yellow_ew, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      :timer.sleep(3_000)
      TrafficLight.drive_next(event.enactment_id, "turn_red_ew")
    end
  end

  transition :turn_red_ew do
    input :yellow_ew, bind({1, s})
    output :red_ew, {1, s}
    output :safe_ns, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      TrafficLight.drive_next(event.enactment_id, "turn_green_ns")
    end
  end

  # … symmetrical NS transitions …

  on_enactment_start do
    TrafficLight.render(options[:frames], event.markings)
    TrafficLight.drive_next(event.enactment_id, "turn_green_ew")
  end

  @doc false
  def drive_next(enactment_id, transition_name) when is_binary(transition_name) do
    enactment_id
    |> Storage.list_live_workitems()
    |> Enum.find(fn wi ->
      wi.state == :enabled and wi.binding_element.transition == transition_name
    end)
    |> case do
      nil ->
        :ok

      %{id: workitem_id} ->
        {:ok, _started} = WorkitemTransition.start_workitem(enactment_id, workitem_id)
        {:ok, _completed} = WorkitemTransition.complete_workitem(enactment_id, {workitem_id, []})
        :ok
    end
  end
end
```

Key tricks:

- The `:safe_ew` / `:safe_ns` places are *interlock tokens*: only one direction can hold one at a time, so `:turn_green_ew` and `:turn_green_ns` are mutually exclusive.
- `signal()` is the unit colour set (`{}`); the actual data does not matter — what matters is *where the token sits*.
- `on_enactment_start` is the bootstrap: it calls `drive_next/2` once, which starts and completes the first workitem. Each `action` block ends by calling `drive_next/2` for the *next* transition, creating a self-driving loop.
- Pattern variant: replace `:timer.sleep` + recursive drive with a `Process.send_after/3` scheduled by `on_enactment_start`, so the runner's task never blocks.

## Choosing between patterns

| Need                                          | Pattern                          |
| --------------------------------------------- | -------------------------------- |
| linear stage progression                      | sequence                         |
| event fans out, follow-ups don't interact     | parallel split                   |
| event has alternative responses               | deferred choice                  |
| every input must be ready                     | generalised AND-join             |
| collect N items before continuing             | thread merge                     |
| retry / idempotent re-delivery / counters     | transmission protocol            |
| recurring state cycle with timed transitions  | state machine + lifecycle drive  |

Real workflows usually compose two or three of these — a parallel split feeding two AND-joins, a state machine whose transitions internally use deferred choice, and so on. The DSL makes the composition just a matter of more `place` and `transition` declarations; nothing changes at the boundary.
