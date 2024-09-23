# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule ColouredFlow.Factory do
  @moduledoc false

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.TestRepo, as: Repo

  use ExMachina.Ecto, repo: Repo

  import ColouredFlow.MultiSet, only: [sigil_b: 2]

  def flow_factory do
    %Schemas.Flow{
      id: Ecto.UUID.generate(),
      name: sequence(:flow_name, &"flow-#{&1}"),
      version: 1,
      data: fn -> %{definition: build_cpnet(:simple_sequence)} end
    }
  end

  def flow_with_cpnet(flow, :simple_sequence) do
    Map.put(flow, :data, %{definition: build_cpnet(:simple_sequence)})
  end

  defp build_cpnet(:simple_sequence) do
    import ColouredFlow.Notation.Colset

    use ColouredFlow.DefinitionHelpers

    %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "pass_through", guard: nil}
      ],
      arcs: [
        build_arc!(
          label: "in",
          place: "input",
          transition: "pass_through",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          label: "out",
          place: "output",
          transition: "pass_through",
          orientation: :t_to_p,
          expression: "bind {1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }
  end

  def enactment_factory do
    %Schemas.Enactment{
      id: Ecto.UUID.generate(),
      flow: fn -> build(:flow) end,
      data: %{initial_markings: []}
    }
  end

  def enactment_with_initial_markings(enactment, markings) when is_list(markings) do
    Map.put(enactment, :data, %{initial_markings: markings})
  end

  def occurrence_factory do
    %Schemas.Occurrence{
      id: Ecto.UUID.generate(),
      enactment: fn -> build(:enactment) end,
      step_number: sequence(:occurrence_step_number, & &1),
      data: fn ->
        %{
          occurrence: %Occurrence{
            binding_element:
              BindingElement.new(
                "pass_through",
                [x: 1],
                [%Marking{place: "integer", tokens: ~b[1]}]
              ),
            free_assignments: [],
            to_produce: [%Marking{place: "output", tokens: ~b[1**2]}]
          }
        }
      end
    }
  end

  def occurrence_with_occurrence(enactment, %Occurrence{} = occurrence) do
    Map.put(enactment, :data, %{occurrence: occurrence})
  end

  def workitem_factory do
    %Schemas.Workitem{
      id: Ecto.UUID.generate(),
      enactment: fn -> build(:enactment) end,
      state: :offered,
      data: fn ->
        %{
          binding_element:
            BindingElement.new(
              "pass_through",
              [x: 1],
              [%Marking{place: "integer", tokens: ~b[1]}]
            )
        }
      end
    }
  end

  def workitem_with_binding_element(workitem, %BindingElement{} = binding_element) do
    Map.put(workitem, :data, %{binding_element: binding_element})
  end

  def snapshot_factory do
    %Schemas.Snapshot{
      enactment: fn -> build(:enactment) end,
      version: sequence(:snapshot_version, & &1),
      data: fn -> %{markings: []} end
    }
  end

  def snapshot_with_markings(snapshot, markings) when is_list(markings) do
    Map.put(snapshot, :data, %{markings: markings})
  end
end
