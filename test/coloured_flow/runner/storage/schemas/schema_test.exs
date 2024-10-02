defmodule ColouredFlow.Runner.Storage.Schemas.SchemaTest do
  use ColouredFlow.RepoCase, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  import ColouredFlow.MultiSet

  test "persists flow" do
    built_flow = build(:flow)
    inserted = insert(built_flow)
    flow = Repo.get(Schemas.Flow, inserted.id)

    assert inserted === flow
  end

  test "persists enactment" do
    built_enactment = build(:enactment)
    inserted = insert(built_enactment)
    enactment = Schemas.Enactment |> Repo.get(inserted.id) |> Repo.preload([:flow])

    assert inserted === enactment
  end

  test "persists enactment with initial_markings" do
    markings = [%Marking{place: "p1", tokens: ~b[1]}]
    built_enactment = :enactment |> build() |> enactment_with_initial_markings(markings)
    inserted = insert(built_enactment)
    enactment = Schemas.Enactment |> Repo.get(inserted.id) |> Repo.preload([:flow])

    assert inserted === enactment
  end

  test "persists occurrence" do
    built_occurrence = build(:occurrence)
    inserted = insert(built_occurrence)
    occurrence = Schemas.Occurrence |> Repo.get(inserted.id) |> Repo.preload(enactment: [:flow])

    assert inserted === occurrence
  end

  test "persists occurrence with occurrence" do
    occurrence = %Occurrence{
      binding_element: %BindingElement{
        transition: "t1",
        binding: [x: 1],
        to_consume: [%Marking{place: "p1", tokens: ~b[1]}]
      },
      free_binding: [x: 1],
      to_produce: [
        %Marking{place: "p2", tokens: ~b[2**1]}
      ]
    }

    built_occurrence = :occurrence |> build() |> occurrence_with_occurrence(occurrence)
    inserted = insert(built_occurrence)
    occurrence = Schemas.Occurrence |> Repo.get(inserted.id) |> Repo.preload(enactment: [:flow])

    assert inserted === occurrence
  end

  test "persists workitem" do
    built_workitem = build(:workitem)
    inserted = insert(built_workitem)
    workitem = Schemas.Workitem |> Repo.get(inserted.id) |> Repo.preload(enactment: [:flow])

    assert inserted === workitem
  end

  test "persists workitem with binding_element" do
    binding_element = %BindingElement{
      transition: "t1",
      binding: [x: 1],
      to_consume: [%Marking{place: "p1", tokens: ~b[1]}]
    }

    built_workitem = :workitem |> build() |> workitem_with_binding_element(binding_element)
    inserted = insert(built_workitem)
    workitem = Schemas.Workitem |> Repo.get(inserted.id) |> Repo.preload(enactment: [:flow])

    assert inserted === workitem
  end

  test "persists snapshot" do
    built_snapshot = build(:snapshot)
    inserted = insert(built_snapshot)

    snapshot =
      Schemas.Snapshot |> Repo.get(inserted.enactment.id) |> Repo.preload(enactment: [:flow])

    assert inserted === snapshot
  end

  test "persists snapshot with markings" do
    marking = %Marking{place: "p1", tokens: ~b[1]}
    built_snapshot = :snapshot |> build() |> snapshot_with_markings([marking])
    inserted = insert(built_snapshot)

    snapshot =
      Schemas.Snapshot |> Repo.get(inserted.enactment.id) |> Repo.preload(enactment: [:flow])

    assert inserted === snapshot
  end
end
