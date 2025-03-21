defmodule ColouredFlow.Runner.Enactment.WorkitemCalibrationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Enactment

  alias ColouredFlow.Runner.Enactment.WorkitemCalibration

  alias ColouredFlow.MultiSet
  import ColouredFlow.MultiSet

  describe "initial_calibrate" do
    test "works" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      state = %Enactment{
        enactment_id: Ecto.UUID.generate()
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert state === calibration.state
      assert [] === calibration.to_withdraw
      assert ~MS[] === calibration.to_produce
    end

    test "produces binding_elements" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert state === calibration.state
      assert [] === calibration.to_withdraw

      binding_elemnt = %BindingElement{
        transition: "pass_through",
        binding: [x: 1],
        to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
      }

      assert ~MS[2**binding_elemnt] === calibration.to_produce
    end

    test "produces missing binding_elements" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}]),
        workitems:
          to_map([
            %Enactment.Workitem{
              id: Ecto.UUID.generate(),
              state: :enabled,
              binding_element: %BindingElement{
                transition: "pass_through",
                binding: [x: 1],
                to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
              }
            }
          ])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert state === calibration.state
      assert [] === calibration.to_withdraw

      binding_elemnt = %BindingElement{
        transition: "pass_through",
        binding: [x: 1],
        to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
      }

      assert ~MS[binding_elemnt] === calibration.to_produce
    end

    test "withdraws some workitems" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings: to_map([%Marking{place: "input", tokens: ~MS[]}]),
        workitems: to_map([workitem])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw

      assert ~MS[] === calibration.to_produce
    end

    test "produces some binding_elements and withdraws some workitems" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 2],
          to_consume: [%Marking{place: "input", tokens: ~MS[2]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings: to_map([%Marking{place: "input", tokens: ~MS[1]}]),
        workitems: to_map([workitem])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw

      binding_elemnt = %BindingElement{
        transition: "pass_through",
        binding: [x: 1],
        to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
      }

      assert ~MS[binding_elemnt] === calibration.to_produce
    end

    test "works with mulitple input places transition" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:generalized_and_join)

      workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "and_join",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input1", tokens: ~MS[1]},
            %Marking{place: "input2", tokens: ~MS[1]},
            %Marking{place: "input3", tokens: ~MS[1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input1", tokens: ~MS[1]},
            %Marking{place: "input2", tokens: ~MS[1]}
          ]),
        workitems: to_map([workitem])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw
      assert ~MS[] === calibration.to_produce
    end
  end

  describe "calibrate after started" do
    # ```mermaid
    # flowchart LR
    #   %% colset int() :: integer()
    #   %% ~MS[3**1]
    #   i((input))
    #   o((output))
    #   pt1[pass_through_1]
    #   pt2[pass_through_2]
    #   i --{1,x}--> pt1
    #   i --{2,x}--> pt2
    #   pt1 & pt2 --> o
    # ```
    test "works when there isn't any workitems to be withdrawn" do
      enactment_id = Ecto.UUID.generate()

      pt1_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      pt1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      pt1_workitem_3 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      pt2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_2",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[2**1]}]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[3**1]}]),
        workitems:
          to_map([
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :started
            },
            pt1_workitem_2,
            pt1_workitem_3,
            pt2_workitem
          ])
      }

      expected_state = %Enactment{
        state
        | workitems:
            to_map([
              %Enactment.Workitem{
                pt1_workitem_1
                | state: :started
              },
              pt1_workitem_2,
              pt1_workitem_3,
              pt2_workitem
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :start, workitems: [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [] === calibration.to_withdraw
    end

    # ```mermaid
    # flowchart LR
    #   %% colset int() :: integer()
    #   %% ~MS[2**1]
    #   i((input))
    #   o((output))
    #   pt1[pass_through_1]
    #   pt2[pass_through_2]
    #   i --{1,x}--> pt1
    #   i --{2,x}--> pt2
    #   pt1 & pt2 --> o
    # ```
    test "withdraws non-enabled workitems from the transition that is derived from the input places" do
      enactment_id = Ecto.UUID.generate()

      pt1_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      pt1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      pt2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_2",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[2**1]}]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}]),
        workitems:
          to_map([
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :started
            },
            pt1_workitem_2,
            pt2_workitem
          ])
      }

      expected_state = %Enactment{
        state
        | workitems:
            to_map([
              %Enactment.Workitem{
                pt1_workitem_1
                | state: :started
              },
              pt1_workitem_2
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :start, workitems: [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [pt2_workitem] === calibration.to_withdraw
    end

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #   %% ~MS[2**1]
    #   i1((input1))
    #   %% ~MS[1]
    #   i2((input2))
    #   %% ~MS[1]
    #   i3((input3))
    #   o((output))
    #   join[And Join]
    #   i1 & i2 & i3 --{1,x}--> join --> o
    # ```
    test "works with mulitple input places" do
      enactment_id = Ecto.UUID.generate()

      aj_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "and_join",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input1", tokens: ~MS[1]},
            %Marking{place: "input2", tokens: ~MS[1]},
            %Marking{place: "input3", tokens: ~MS[1]}
          ]
        }
      }

      aj_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "and_join",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input1", tokens: ~MS[1]},
            %Marking{place: "input2", tokens: ~MS[1]},
            %Marking{place: "input3", tokens: ~MS[1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings:
          to_map([
            %Marking{place: "input1", tokens: ~MS[2**1]},
            %Marking{place: "input2", tokens: ~MS[1]},
            %Marking{place: "input3", tokens: ~MS[1]}
          ]),
        workitems:
          to_map([
            %Enactment.Workitem{
              aj_workitem_1
              | state: :started
            },
            aj_workitem_2
          ])
      }

      expected_state = %Enactment{
        state
        | workitems:
            to_map([
              %Enactment.Workitem{
                aj_workitem_1
                | state: :started
              }
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :start, workitems: [aj_workitem_1])

      assert expected_state === calibration.state
      assert [aj_workitem_2] === calibration.to_withdraw
    end
  end

  describe "calibrate after completed" do
    import ColouredFlow.CpnetBuilder

    alias ColouredFlow.Enactment.Occurrence

    test "produces no workitems when no new binding_elements enabled" do
      cpnet = build_cpnet(:thread_merge)

      b2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_2",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[2**1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}]),
        workitems: to_map([])
      }

      occurrence = %Occurrence{
        binding_element: b2_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings: to_map([%Marking{place: "merge", tokens: ~MS[1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{b2_workitem, occurrence}]
        )

      assert expected_state === calibration.state
      assert MultiSet.new() === calibration.to_produce
    end

    test "produces new workitems without considering the in-progress workitems" do
      cpnet =
        :deferred_choice
        |> ColouredFlow.CpnetBuilder.build_cpnet()
        |> ColouredFlow.CpnetBuilder.update_arc!(
          {:p_to_t, "deferred_choice_2", "place"},
          expression: "bind {2,x}"
        )

      pt_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      dc1_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "deferred_choice_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "place", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~MS[1]},
            %Marking{place: "place", tokens: ~MS[1]}
          ]),
        workitems: to_map([dc1_workitem])
      }

      occurrence = %Occurrence{
        binding_element: pt_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "place", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings: to_map([%Marking{place: "place", tokens: ~MS[2**1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{pt_workitem, occurrence}]
        )

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "deferred_choice_1",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place", tokens: ~MS[1]}]
               }
             ]) === calibration.to_produce
    end

    test "produces new workitems when there is some live workitems at the transition" do
      cpnet = build_cpnet(:thread_merge)

      b1_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      tm_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "thread_merge",
          binding: [],
          to_consume: [%Marking{place: "merge", tokens: ~MS[2**1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~MS[1]},
            %Marking{place: "merge", tokens: ~MS[2**1]}
          ]),
        workitems: to_map([tm_workitem])
      }

      occurrence = %Occurrence{
        binding_element: b1_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings: to_map([%Marking{place: "merge", tokens: ~MS[3**1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{b1_workitem, occurrence}]
        )

      assert expected_state === calibration.state
      assert MultiSet.new() === calibration.to_produce
    end

    test "completes mulitple workitems and produces new workitems for mulitple transitions" do
      cpnet = build_cpnet(:thread_merge)

      b1_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      b1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}]),
        workitems: to_map([])
      }

      b1_occurrence_1 = %Occurrence{
        binding_element: b1_workitem_1.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~MS[1]}]
      }

      b1_occurrence_2 = %Occurrence{
        binding_element: b1_workitem_2.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 2,
          markings: to_map([%Marking{place: "merge", tokens: ~MS[2**1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [
            {b1_workitem_1, b1_occurrence_1},
            {b1_workitem_2, b1_occurrence_2}
          ]
        )

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "thread_merge",
                 binding: [],
                 to_consume: [%Marking{place: "merge", tokens: ~MS[2**1]}]
               }
             ]) === calibration.to_produce
    end

    test "produces new workitems for one transition" do
      cpnet = build_cpnet(:thread_merge)

      b1_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~MS[1]},
            %Marking{place: "merge", tokens: ~MS[1]}
          ]),
        workitems: to_map([])
      }

      b1_occurrence = %Occurrence{
        binding_element: b1_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings: to_map([%Marking{place: "merge", tokens: ~MS[2**1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{b1_workitem, b1_occurrence}]
        )

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "thread_merge",
                 binding: [],
                 to_consume: [%Marking{place: "merge", tokens: ~MS[2**1]}]
               }
             ]) === calibration.to_produce
    end

    test "produces new workitems for mulitple transitions" do
      cpnet = build_cpnet(:deferred_choice)

      pt_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[1]}]),
        workitems: to_map([])
      }

      pt_occurrence = %Occurrence{
        binding_element: pt_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "place", tokens: ~MS[1]}]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings: to_map([%Marking{place: "place", tokens: ~MS[1]}])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{pt_workitem, pt_occurrence}]
        )

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "deferred_choice_1",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place", tokens: ~MS[1]}]
               },
               %BindingElement{
                 transition: "deferred_choice_2",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place", tokens: ~MS[1]}]
               }
             ]) === calibration.to_produce
    end

    test "produces new workitems into mulitple places for mulitple transitions" do
      cpnet = build_cpnet(:parallel_split)

      ps_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "parallel_split",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[1]}]),
        workitems: to_map([])
      }

      ps_occurrence = %Occurrence{
        binding_element: ps_workitem.binding_element,
        free_binding: [],
        to_produce: [
          %Marking{place: "place_1", tokens: ~MS[1]},
          %Marking{place: "place_2", tokens: ~MS[1]}
        ]
      }

      expected_state = %Enactment{
        state
        | version: 1,
          markings:
            to_map([
              %Marking{place: "place_1", tokens: ~MS[1]},
              %Marking{place: "place_2", tokens: ~MS[1]}
            ])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{ps_workitem, ps_occurrence}]
        )

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "pass_through_1",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place_1", tokens: ~MS[1]}]
               },
               %BindingElement{
                 transition: "pass_through_2",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place_2", tokens: ~MS[1]}]
               }
             ]) === calibration.to_produce
    end

    test "produces new workitems when consumed zero tokens from input places" do
      cpnet =
        :simple_sequence
        |> ColouredFlow.CpnetBuilder.build_cpnet()
        |> ColouredFlow.CpnetBuilder.update_arc!(
          {:p_to_t, "pass_through", "input"},
          expression: "bind {0,x}"
        )

      pt_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[]}]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~MS[1]}
          ]),
        workitems: to_map([])
      }

      occurrence = %Occurrence{
        binding_element: pt_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "output", tokens: ~MS[1]}]
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: cpnet,
          workitem_occurrences: [{pt_workitem, occurrence}]
        )

      expected_state = %Enactment{
        state
        | version: 1,
          markings:
            to_map([
              %Marking{place: "input", tokens: ~MS[1]},
              %Marking{place: "output", tokens: ~MS[1]}
            ])
      }

      assert expected_state === calibration.state

      assert MultiSet.new([
               %BindingElement{
                 transition: "pass_through",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "input", tokens: ~MS[]}]
               }
             ]) === calibration.to_produce
    end
  end

  describe "calibrate after complete_e" do
    setup do
      use ColouredFlow.DefinitionHelpers

      import ColouredFlow.Notation

      # ```mermaid
      # flowchart TB
      #   %% colset int() :: integer()
      #
      #   i((input))
      #   im((intermediate))
      #   o((output))
      #
      #   b1[branch_1]
      #   b2[branch_2]
      #   pt[pass_through]
      #
      #   i --bind {1,x}--> b1 --{1,x}--> im
      #   i --bind {2,x}--> b2 --{1,x}--> im
      #   im --bind {1,x}--> pt --{1,x}--> o
      # ```
      cpnet =
        %ColouredPetriNet{
          colour_sets: [
            colset(int() :: integer())
          ],
          places: [
            %Place{name: "input", colour_set: :int},
            %Place{name: "intermediate", colour_set: :int},
            %Place{name: "output", colour_set: :int}
          ],
          transitions: [
            build_transition!(name: "branch_1"),
            build_transition!(name: "branch_2"),
            build_transition!(name: "pass_through")
          ],
          arcs: [
            arc(branch_1 <~ input :: "bind {1, x}"),
            arc(branch_2 <~ input :: "bind {2, x}"),
            arc(branch_1 ~> intermediate :: "{1, x}"),
            arc(branch_2 ~> intermediate :: "{1, x}"),
            arc(pass_through <~ intermediate :: "bind {1, x}"),
            arc(pass_through ~> output :: "{1, x}")
          ],
          variables: [
            var(x :: int())
          ]
        }

      assert {:ok, cpnet} =
               cpnet
               |> ColouredFlow.Builder.build()
               |> ColouredFlow.Validators.run()

      %{cpnet: cpnet}
    end

    test "withdraws and produces workitems", %{cpnet: cpnet} do
      enactment_id = Ecto.UUID.generate()

      br1_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      br1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[1]}]
        }
      }

      br2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [%Marking{place: "input", tokens: ~MS[2**1]}]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings: to_map([%Marking{place: "input", tokens: ~MS[2**1]}]),
        workitems:
          to_map([
            br1_workitem_2,
            br2_workitem
          ])
      }

      workitem_occurrences = [
        {
          %{br1_workitem_1 | state: :completed},
          %Occurrence{
            binding_element: br1_workitem_1.binding_element,
            free_binding: [],
            to_produce: [%Marking{place: "intermediate", tokens: ~MS[1]}]
          }
        }
      ]

      calibration =
        WorkitemCalibration.calibrate(state, :complete_e,
          cpnet: cpnet,
          workitem_occurrences: workitem_occurrences
        )

      expected_state = %Enactment{
        state
        | markings:
            to_map([
              %Marking{place: "input", tokens: ~MS[1]},
              %Marking{place: "intermediate", tokens: ~MS[1]}
            ]),
          workitems:
            to_map([
              br1_workitem_2
            ]),
          version: 1
      }

      assert expected_state === calibration.state
      assert [br2_workitem] === calibration.to_withdraw

      assert MultiSet.new([
               %BindingElement{
                 transition: "pass_through",
                 binding: [x: 1],
                 to_consume: [
                   %Marking{place: "intermediate", tokens: ~MS[1]}
                 ]
               }
             ]) === calibration.to_produce
    end
  end

  defp to_map([]), do: %{}

  defp to_map([%Enactment.Workitem{} | _rest] = workitems) do
    Map.new(workitems, &{&1.id, &1})
  end

  defp to_map([%Marking{} | _rest] = markings) do
    Map.new(markings, &{&1.place, &1})
  end
end
