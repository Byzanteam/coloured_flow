# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule ColouredFlow.Factory do
  @moduledoc false

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas
  alias ColouredFlow.TestRepo, as: Repo

  use ExMachina.Ecto, repo: Repo

  import ColouredFlow.MultiSet, only: :sigils

  def flow_factory do
    %Schemas.Flow{
      id: Ecto.UUID.generate(),
      name: sequence(:flow_name, &"flow-#{&1}"),
      definition: fn -> ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence) end
    }
  end

  def flow_with_cpnet(flow, %ColouredPetriNet{} = cpnet) do
    Map.put(flow, :definition, cpnet)
  end

  def flow_with_cpnet(flow, flow_name) when is_atom(flow_name) do
    Map.put(flow, :definition, ColouredFlow.CpnetBuilder.build_cpnet(flow_name))
  end

  def enactment_factory do
    %Schemas.Enactment{
      id: Ecto.UUID.generate(),
      flow: fn -> build(:flow) end,
      initial_markings: []
    }
  end

  def enactment_with_initial_markings(enactment, markings) when is_list(markings) do
    Map.put(enactment, :initial_markings, markings)
  end

  def occurrence_factory do
    %Schemas.Occurrence{
      enactment: fn -> build(:enactment) end,
      workitem: fn -> build(:workitem) end,
      step_number: sequence(:occurrence_step_number, & &1),
      occurrence: fn ->
        %Occurrence{
          binding_element:
            BindingElement.new(
              "pass_through",
              [x: 1],
              [%Marking{place: "integer", tokens: ~MS[1]}]
            ),
          free_binding: [],
          to_produce: [%Marking{place: "output", tokens: ~MS[1**2]}]
        }
      end
    }
  end

  def occurrence_with_occurrence(enactment, %Occurrence{} = occurrence) do
    Map.put(enactment, :occurrence, occurrence)
  end

  def workitem_factory do
    %Schemas.Workitem{
      id: Ecto.UUID.generate(),
      enactment: fn -> build(:enactment) end,
      state: :enabled,
      binding_element:
        BindingElement.new(
          "pass_through",
          [x: 1],
          [%Marking{place: "integer", tokens: ~MS[1]}]
        )
    }
  end

  def workitem_with_binding_element(workitem, %BindingElement{} = binding_element) do
    Map.put(workitem, :binding_element, binding_element)
  end

  def snapshot_factory do
    %Schemas.Snapshot{
      enactment: fn -> build(:enactment) end,
      version: sequence(:snapshot_version, & &1),
      markings: []
    }
  end

  def snapshot_with_markings(snapshot, markings) when is_list(markings) do
    Map.put(snapshot, :markings, markings)
  end
end
