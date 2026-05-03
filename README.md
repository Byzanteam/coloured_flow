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
  %% colset signal() :: {}

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

    r_ew --{1,s}--> tg_ew
    tg_ew --{1,s}--> g_ew
    g_ew --{1,s}--> ty_ew
    ty_ew --{1,s}--> y_ew
    y_ew --{1,s}--> tr_ew
    tr_ew --{1,s}--> r_ew
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

    r_ns --{1,s}--> tg_ns
    tg_ns --{1,s}--> g_ns
    g_ns --{1,s}--> ty_ns
    ty_ns --{1,s}--> y_ns
    y_ns --{1,s}--> tr_ns
    tr_ns --{1,s}--> r_ns
  end

  %% safe
  %% ~b[{}]
  s_ew((safe_ew))
  s_ns((safe_ns))

  tr_ns --{1,s}--> s_ew
  s_ew --{1,s}--> tg_ew
  tr_ew --{1,s}--> s_ns
  s_ns --{1,s}--> tg_ns
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
  [
    {0, ColouredFlow.Runner.Migrations.V0},
    {1, ColouredFlow.Runner.Migrations.V1},
    {2, ColouredFlow.Runner.Migrations.V2},
    {3, ColouredFlow.Runner.Migrations.V3}
  ],
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

The workflow itself is a `ColouredFlow.DSL` module. Each transition's
`action do ... end` body re-renders the Kino frames from the latest markings,
sleeps to keep the just-fired colour on screen, then drives the next workitem to
completion via a small `drive_next/2` helper. `on_enactment_start` bootstraps
the cycle by driving `turn_green_ew`. The `:lifecycle_hooks` option carries the
per-place Kino frames map into every callback through `options[:frames]`.

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

  transition :turn_green_ns do
    input :red_ns, bind({1, s})
    input :safe_ns, bind({1, s})
    output :green_ns, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      :timer.sleep(10_000)
      TrafficLight.drive_next(event.enactment_id, "turn_yellow_ns")
    end
  end

  transition :turn_yellow_ns do
    input :green_ns, bind({1, s})
    output :yellow_ns, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      :timer.sleep(3_000)
      TrafficLight.drive_next(event.enactment_id, "turn_red_ns")
    end
  end

  transition :turn_red_ns do
    input :yellow_ns, bind({1, s})
    output :red_ns, {1, s}
    output :safe_ew, {1, s}

    action do
      TrafficLight.render(options[:frames], event.markings)
      TrafficLight.drive_next(event.enactment_id, "turn_green_ew")
    end
  end

  on_enactment_start do
    TrafficLight.render(options[:frames], event.markings)
    TrafficLight.drive_next(event.enactment_id, "turn_green_ew")
  end

  def to_kino do
    lights =
      for color <- [:red, :yellow, :green], dir <- [:ew, :ns] do
        {"#{color}_#{dir}", Kino.Frame.new(placeholder: false)}
      end

    headers = [Kino.Text.new("EW"), Kino.Text.new("NS")]
    grid = Kino.Layout.grid(headers ++ Keyword.values(lights), columns: 2)

    {grid, lights}
  end

  @doc false
  def render(nil, _markings), do: :ok

  def render(frames, markings) when is_map(frames) do
    occupied = MapSet.new(Map.keys(markings))

    Enum.each(frames, fn {place_name, frame} ->
      Kino.Frame.render(frame, light_symbol(place_name, MapSet.member?(occupied, place_name)))
    end)
  end

  defp light_symbol(_place, false), do: Kino.Text.new("⚫️", terminal: true)

  defp light_symbol(place_name, true) do
    emoji =
      case place_name do
        "red_" <> _ -> "🔴"
        "yellow_" <> _ -> "🟡"
        "green_" <> _ -> "🟢"
        _ -> "⚫️"
      end

    Kino.Text.new(emoji, terminal: true)
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

defmodule TrafficLight.Supervisor do
  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(init_arg \\ []) when is_list(init_arg) do
    Process.whereis(__MODULE__) && Supervisor.stop(__MODULE__)
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    Supervisor.init(
      [{Task.Supervisor, name: TrafficLight.TaskSup}],
      strategy: :one_for_one
    )
  end
end
```

#### Run

```elixir
alias ColouredFlow.Runner.Storage.Repo
alias ColouredFlow.Runner.Storage.Schemas

Logger.configure(level: :info)

flow =
  %Schemas.Flow{}
  |> Ecto.Changeset.cast(
    %{name: TrafficLight.__cpn__(:name), definition: TrafficLight.cpnet()},
    [:name, :definition]
  )
  |> Repo.insert!([])

{:ok, enactment} = TrafficLight.insert_enactment(flow.id)

{grid, lights} = TrafficLight.to_kino()
frames = Map.new(lights)

{:ok, _sup} = TrafficLight.Supervisor.start_link()

{:ok, _enactment_pid} =
  TrafficLight.start_enactment(enactment.id,
    lifecycle_hooks: {TrafficLight, [frames: frames]}
  )

grid
```
