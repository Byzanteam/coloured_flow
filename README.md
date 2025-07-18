# ColouredFlow

ColouredFlow is a workflow engine based on
[Coloured Petri Nets (CPN)](https://github.com/lmkr/cpnbook). It provides a
flexible and powerful way to model business processes and archive automation.

## Key Features

- **💻 100% Elixir-based Implementation**: Includes
  [CPN ML Language](https://github.com/lmkr/cpnbook)
- **🕸️ Distributed by Design**: Enactments (Workflow instances) are isolated,
  supporting true concurrency and fault tolerance
- **🔧 Complete Workflow Control**: Full implementation of 40+
  [workflow control patterns](http://www.workflowpatterns.com/patterns/control/)
- **📊 Event-sourced Enactments**: Enactments(Workflow instances) and
  Occurrences for detailed analysis and statistics
- **💾 Abstracted Storage**: In-memory storage for testing; Postgres for
  production
- **📝 DSL**: A simple DSL for defining workflows effectively
- **📡 Built-in Telemetry**: Comprehensive observability and debugging

> [!WARNING]\
> The document is WIP. Check examples at [examples folder](./examples).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `coloured_flow` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:coloured_flow, "~> 0.1.0"}
  ]
end
```

## Usage

Here is an example of how to use the `coloured_flow` package to model and
execute a traffic light system using a Coloured Petri Net.

### Example: Traffic Light

```elixir
Mix.install(
  [
    {:coloured_flow, github: "Byzanteam/coloured_flow"},
    {:kino, "~> 0.14.1"}
  ],
  config: [
    coloured_flow: [
      {
        ColouredFlow.Runner.Storage,
        [
          repo: TrafficLight.Repo,
          storage: ColouredFlow.Runner.Storage.Default
        ]
      }
    ],
    traffic_light: [
      database_url: "ecto://postgres:postgres@localhost/coloured_flow"
    ]
  ]
)
```

#### Preparation

We assume you have a PostgreSQL database running, and the `coloured_flow`
database exists. If not, please create the `coloured_flow` database before
proceeding.

The default database URL is `ecto://postgres:postgres@localhost/coloured_flow`,
you can change it in the above setup block if your database URL is different.

#### Coloured Petri Net graph

<details>
<summary>Open to view the graph</summary>

```mermaid
flowchart TB
  %% colset unit() :: {}

  subgraph EW
    %% places
    %% ~b[{}]
    r_ew((red_ew))
    g_ew((green_ew))
    y_ew((yellow_ew))

    %% transitions
    tr_ew[turn_red_ew]
    tg_ew[turn_green_ew]
    ty_ew[turn_yellow_ew]

    r_ew --{1,u}--> tg_ew
    tg_ew --{1,u}--> g_ew
    g_ew --{1,u}--> ty_ew
    ty_ew --{1,u}--> y_ew
    y_ew --{1,u}--> tr_ew
    tr_ew --{1,u}--> r_ew
  end

  subgraph NS
    %% places
    %% ~b[{}]
    r_ns((red_ns))
    g_ns((green_ns))
    y_ns((yellow_ns))

    %% transitions
    tr_ns[turn_red_ns]
    tg_ns[turn_green_ns]
    ty_ns[turn_yellow_ns]

    r_ns --{1,u}--> tg_ns
    tg_ns --{1,u}--> g_ns
    g_ns --{1,u}--> ty_ns
    ty_ns --{1,u}--> y_ns
    y_ns --{1,u}--> tr_ns
    tr_ns --{1,u}--> r_ns
  end

  %% safe
  %% ~b[{}]
  s_ew((safe_ew))
  s_ns((safe_ns))

  tr_ns --{1,u}--> s_ew
  s_ew --{1,u}--> tg_ew
  tr_ew --{1,u}--> s_ns
  s_ns --{1,u}--> tg_ns
```

</details>

#### Setup

```elixir
defmodule TrafficLight.Repo do
  use Ecto.Repo,
    otp_app: :coloured_flow,
    adapter: Ecto.Adapters.Postgres
end

repo_pid =
  case TrafficLight.Repo.start_link(url: Application.fetch_env!(:traffic_light, :database_url)) do
    {:ok, pid} -> pid
    {:error, {:already_started, pid}} -> pid
    {:error, reason} -> raise inspect(reason)
  end

Ecto.Migrator.run(
  TrafficLight.Repo,
  [{0, ColouredFlow.Runner.Migrations.V0}],
  :up,
  all: true
)

IO.inspect("Repo started: #{inspect(repo_pid)}")

supervisor_pid =
  case ColouredFlow.Runner.Supervisor.start_link() do
    {:ok, pid} -> pid
    {:error, {:already_started, pid}} -> pid
    {:error, reason} -> raise inspect(reason)
  end

IO.inspect("Runner supervisor started: #{inspect(supervisor_pid)}")

"Database setup"
```

#### Flow modules

```elixir
defmodule TrafficLight do
  alias ColouredFlow.Runner.Storage.Schemas

  def flow do
    alias ColouredFlow.Definition.ColouredPetriNet
    alias ColouredFlow.Definition.Place
    alias ColouredFlow.Definition.Variable

    import ColouredFlow.Builder.DefinitionHelper
    import ColouredFlow.Notation.Colset

    %ColouredPetriNet{
      colour_sets: [
        colset(unit() :: {})
      ],
      places:
        Enum.map(
          ~w[red_ew green_ew yellow_ew red_ns green_ns yellow_ns safe_ew safe_ns],
          fn name ->
            %Place{name: name, colour_set: :unit}
          end
        ),
      transitions:
        Enum.map(
          ~w[turn_red_ew turn_green_ew turn_yellow_ew turn_red_ns turn_green_ns turn_yellow_ns],
          &build_transition!(name: &1)
        ),
      arcs:
        [
          arc(turn_green_ew <~ red_ew :: "bind {1, u}"),
          arc(turn_green_ew ~> green_ew :: "{1, u}"),
          arc(turn_yellow_ew <~ green_ew :: "bind {1, u}"),
          arc(turn_yellow_ew ~> yellow_ew :: "{1, u}"),
          arc(turn_red_ew <~ yellow_ew :: "bind {1, u}"),
          arc(turn_red_ew ~> red_ew :: "{1, u}")
        ] ++
          [
            arc(turn_green_ns <~ red_ns :: "bind {1, u}"),
            arc(turn_green_ns ~> green_ns :: "{1, u}"),
            arc(turn_yellow_ns <~ green_ns :: "bind {1, u}"),
            arc(turn_yellow_ns ~> yellow_ns :: "{1, u}"),
            arc(turn_red_ns <~ yellow_ns :: "bind {1, u}"),
            arc(turn_red_ns ~> red_ns :: "{1, u}")
          ] ++
          [
            arc(turn_red_ns ~> safe_ew :: "{1, u}"),
            arc(turn_green_ew <~ safe_ew :: "bind {1, u}"),
            arc(turn_red_ew ~> safe_ns :: "{1, u}"),
            arc(turn_green_ns <~ safe_ns :: "bind {1, u}")
          ],
      variables: [
        %Variable{name: :u, colour_set: :unit}
      ]
    }
  end

  def setup_flow do
    %Schemas.Flow{}
    |> Ecto.Changeset.cast(
      %{
        name: "TrafficLight",
        definition: flow()
      },
      [:name, :definition]
    )
    |> TrafficLight.Repo.insert!()
  end

  def setup_enactment(flow, initial_markings) do
    %Schemas.Enactment{}
    |> Ecto.Changeset.cast(%{initial_markings: initial_markings}, [:initial_markings])
    |> Ecto.Changeset.put_assoc(:flow, flow)
    |> TrafficLight.Repo.insert!()
  end

  def start_enactment(flow) do
    import ColouredFlow.MultiSet, only: :sigils

    enactment =
      TrafficLight.setup_enactment(
        flow,
        [
          %{place: "red_ew", tokens: ~MS[{}]},
          %{place: "red_ns", tokens: ~MS[{}]},
          %{place: "safe_ew", tokens: ~MS[{}]}
        ]
      )

    {:ok, enactment_pid} = ColouredFlow.Runner.Enactment.Supervisor.start_enactment(enactment.id)

    {enactment, enactment_pid}
  end

  def to_kino do
    lights =
      for color <- [:red, :yellow, :green], dir <- [:ew, :ns] do
        {"#{color}_#{dir}", Kino.Frame.new(placeholder: false)}
      end

    grid = Kino.Layout.grid([EW, NS] ++ Keyword.values(lights), columns: 2)

    {grid, lights}
  end
end

defmodule TrafficLight.WorkitemPubSub do
  use GenServer

  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.Runner.Worklist.WorkitemStream

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl GenServer
  def init(init_arg) do
    enactment_id = Keyword.fetch!(init_arg, :enactment_id)

    {:ok, %{enactment_id: enactment_id}, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    stream_task = start_stream(enactment_id: state.enactment_id)

    {:noreply, Map.put(state, :stream_task, stream_task)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Task.shutdown(state.stream_task)
  end

  @delay 1000
  defp start_stream(options) when is_list(options) do
    import Ecto.Query

    delay = Keyword.get(options, :delay, @delay)
    enactment_id = Keyword.fetch!(options, :enactment_id)

    Task.async(fn ->
      stream =
        Stream.resource(
          fn -> nil end,
          fn cursor ->
            [after_cursor: cursor]
            |> WorkitemStream.live_query()
            |> where(enactment_id: ^enactment_id)
            |> WorkitemStream.list_live()
            |> case do
              :end_of_stream ->
                Process.sleep(delay)

                {[], cursor}

              {workitems, cursor} ->
                {workitems, cursor}
            end
          end,
          fn _cursor -> :ok end
        )

      stream
      |> Stream.each(fn %Schemas.Workitem{} = workitem ->
        send(get_light(workitem), {:workitem, workitem})
      end)
      |> Stream.run()
    end)
  end

  defp get_light(%Schemas.Workitem{} = workitem) do
    dir =
      case workitem.binding_element.transition do
        "turn_red_" <> dir -> dir
        "turn_yellow_" <> dir -> dir
        "turn_green_" <> dir -> dir
      end

    case dir do
      "ew" -> TrafficLight.EWLight
      "ns" -> TrafficLight.NSLight
    end
  end
end

defmodule TrafficLight.DirectionalLight do
  use GenServer

  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage.Schemas

  def start_link(init_arg) when is_list(init_arg) do
    {name, init_arg} = Keyword.pop!(init_arg, :name)

    GenServer.start_link(__MODULE__, init_arg, name: name)
  end

  @impl GenServer
  def init(init_arg) do
    enactment_id = Keyword.fetch!(init_arg, :enactment_id)
    enactment_pid = Keyword.fetch!(init_arg, :enactment_pid)
    direction = Keyword.fetch!(init_arg, :direction)
    lights = Keyword.fetch!(init_arg, :lights)

    {
      :ok,
      %{
        enactment_id: enactment_id,
        enactment_pid: enactment_pid,
        direction: direction,
        lights: lights
      },
      {:continue, :tick}
    }
  end

  @impl GenServer
  def handle_info({:workitem, %Schemas.Workitem{state: :enabled} = workitem}, state) do
    started_workitem = start_workitem(state.enactment_id, workitem.id)

    schedule_turn(started_workitem, workitem.inserted_at)

    {:noreply, state, {:continue, :tick}}
  end

  def handle_info({:workitem, %Schemas.Workitem{state: workitem_state}}, state)
      when workitem_state in unquote(Workitem.__in_progress_states__()) do
    # ignore in progress workitems

    {:noreply, state, {:continue, :tick}}
  end

  def handle_info({:turn, _color, %Workitem{} = workitem}, state) do
    {:ok, _completed_workitem} =
      WorkitemTransition.complete_workitem(state.enactment_id, {workitem.id, []})

    {:noreply, state, {:continue, :tick}}
  end

  @impl GenServer
  def handle_continue(:tick, state) do
    marking_places = get_marking_places(state.enactment_pid, state.direction)
    control(marking_places, state.lights)

    {:noreply, state}
  end

  defp start_workitem(enactment_id, workitem_id) do
    {:ok, started_workitem} =
      WorkitemTransition.start_workitem(enactment_id, workitem_id)

    started_workitem
  end

  @color_delay %{
    red: 3_000,
    yellow: 10_000,
    green: 0
  }

  defp schedule_turn(%Workitem{} = workitem, started_at) do
    color = get_color(workitem)
    delay = Map.fetch!(@color_delay, color)

    deplay =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.diff(started_at, :millisecond)
      |> then(&Kernel.-(delay, &1))
      |> Kernel.max(0)

    Process.send_after(self(), {:turn, color, workitem}, deplay)
  end

  defp get_color(%Workitem{} = workitem) do
    case workitem.binding_element.transition do
      "turn_red" <> _dir -> :red
      "turn_yellow" <> _dir -> :yellow
      "turn_green" <> _dir -> :green
    end
  end

  defp get_marking_places(enactment_pid, direction) do
    direction = Atom.to_string(direction)

    enactment_pid
    |> :sys.get_state()
    |> Map.get(:markings)
    |> Map.keys()
    |> Enum.filter(&String.ends_with?(&1, direction))
  end

  defp control(marking_places, lights) do
    Enum.each(lights, fn {place_name, frame} ->
      light_symbol = light_symbol(place_name, place_name in marking_places)

      Kino.Frame.render(frame, light_symbol)
    end)
  end

  defp light_symbol(color, on?)

  defp light_symbol(color, true) do
    emoji =
      case color do
        "red" <> _dir -> "🔴"
        "yellow" <> _dir -> "🟡"
        "green" <> _dir -> "🟢"
      end

    Kino.Text.new(emoji, terminal: true)
  end

  defp light_symbol(_color, false) do
    Kino.Text.new("⚫️", terminal: true)
  end
end

defmodule TrafficLight.Supervisor do
  use Supervisor

  alias TrafficLight.DirectionalLight
  alias TrafficLight.WorkitemPubSub

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(init_arg \\ []) when is_list(init_arg) do
    Process.whereis(__MODULE__) && Supervisor.stop(__MODULE__)
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(init_arg) do
    enactment_id = Keyword.fetch!(init_arg, :enactment_id)
    enactment_pid = Keyword.fetch!(init_arg, :enactment_pid)
    lights = Keyword.fetch!(init_arg, :lights)

    ew_lights = Enum.filter(lights, fn {name, _frame} -> String.ends_with?(name, "ew") end)
    ns_lights = Enum.filter(lights, fn {name, _frame} -> String.ends_with?(name, "ns") end)

    light_options = [enactment_id: enactment_id, enactment_pid: enactment_pid]

    children = [
      {WorkitemPubSub, [enactment_id: enactment_id]},
      Supervisor.child_spec(
        {DirectionalLight,
         [name: TrafficLight.EWLight, direction: :ew, lights: ew_lights] ++ light_options},
        id: TrafficLight.EWLight
      ),
      Supervisor.child_spec(
        {DirectionalLight,
         [name: TrafficLight.NSLight, direction: :ns, lights: ns_lights] ++ light_options},
        id: TrafficLight.NSLight
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

#### Run

```elixir
Logger.configure(level: :info)
flow = TrafficLight.setup_flow()
{enactment, enactment_pid} = TrafficLight.start_enactment(flow)

{grid, lights} = TrafficLight.to_kino()

{:ok, pid} =
  TrafficLight.Supervisor.start_link(
    enactment_id: enactment.id,
    enactment_pid: enactment_pid,
    lights: lights
  )

grid
```
