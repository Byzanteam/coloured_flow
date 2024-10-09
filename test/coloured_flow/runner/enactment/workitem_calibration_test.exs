defmodule ColouredFlow.Runner.Enactment.WorkitemCalibrationTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment

  alias ColouredFlow.Runner.Enactment.WorkitemCalibration

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
      assert ~b[] === calibration.to_produce
    end

    test "produces binding_elements" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[2**1]}
          ])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert state === calibration.state
      assert [] === calibration.to_withdraw

      binding_elemnt = %BindingElement{
        transition: "pass_through",
        binding: [x: 1],
        to_consume: [%Marking{place: "input", tokens: ~b[1]}]
      }

      assert ~b[2**binding_elemnt] === calibration.to_produce
    end

    test "produces missing binding_elements" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[2**1]}
          ]),
        workitems:
          to_map([
            %Enactment.Workitem{
              id: Ecto.UUID.generate(),
              state: :enabled,
              binding_element: %BindingElement{
                transition: "pass_through",
                binding: [x: 1],
                to_consume: [
                  %Marking{place: "input", tokens: ~b[1]}
                ]
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
        to_consume: [%Marking{place: "input", tokens: ~b[1]}]
      }

      assert ~b[binding_elemnt] === calibration.to_produce
    end

    test "withdraws some workitems" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[]}
          ]),
        workitems:
          to_map([
            workitem
          ])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw

      assert ~b[] === calibration.to_produce
    end

    test "produces some binding_elements and withdraws some workitems" do
      cpnet = ColouredFlow.CpnetBuilder.build_cpnet(:simple_sequence)

      workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 2],
          to_consume: [
            %Marking{place: "input", tokens: ~b[2]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[1]}
          ]),
        workitems:
          to_map([
            workitem
          ])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw

      binding_elemnt = %BindingElement{
        transition: "pass_through",
        binding: [x: 1],
        to_consume: [%Marking{place: "input", tokens: ~b[1]}]
      }

      assert ~b[binding_elemnt] === calibration.to_produce
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
            %Marking{place: "input1", tokens: ~b[1]},
            %Marking{place: "input2", tokens: ~b[1]},
            %Marking{place: "input3", tokens: ~b[1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: Ecto.UUID.generate(),
        markings:
          to_map([
            %Marking{place: "input1", tokens: ~b[1]},
            %Marking{place: "input2", tokens: ~b[1]}
          ]),
        workitems:
          to_map([
            workitem
          ])
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: %{}} === calibration.state
      assert [workitem] === calibration.to_withdraw
      assert ~b[] === calibration.to_produce
    end
  end

  describe "calibrate after allocate" do
    # ```mermaid
    # flowchart LR
    #   %% colset int() :: integer()
    #   %% ~b[3**1]
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
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt1_workitem_3 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_2",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[2**1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[3**1]}
          ]),
        workitems:
          to_map([
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :allocated
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
                | state: :allocated
              },
              pt1_workitem_2,
              pt1_workitem_3,
              pt2_workitem
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, workitems: [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [] === calibration.to_withdraw
    end

    # ```mermaid
    # flowchart LR
    #   %% colset int() :: integer()
    #   %% ~b[2**1]
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
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :enabled,
        binding_element: %BindingElement{
          transition: "pass_through_2",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[2**1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings:
          to_map([
            %Marking{place: "input", tokens: ~b[2**1]}
          ]),
        workitems:
          to_map([
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :allocated
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
                | state: :allocated
              },
              pt1_workitem_2
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, workitems: [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [pt2_workitem] === calibration.to_withdraw
    end

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #   %% ~b[2**1]
    #   i1((input1))
    #   %% ~b[1]
    #   i2((input2))
    #   %% ~b[1]
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
            %Marking{place: "input1", tokens: ~b[1]},
            %Marking{place: "input2", tokens: ~b[1]},
            %Marking{place: "input3", tokens: ~b[1]}
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
            %Marking{place: "input1", tokens: ~b[1]},
            %Marking{place: "input2", tokens: ~b[1]},
            %Marking{place: "input3", tokens: ~b[1]}
          ]
        }
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings:
          to_map([
            %Marking{place: "input1", tokens: ~b[2**1]},
            %Marking{place: "input2", tokens: ~b[1]},
            %Marking{place: "input3", tokens: ~b[1]}
          ]),
        workitems:
          to_map([
            %Enactment.Workitem{
              aj_workitem_1
              | state: :allocated
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
                | state: :allocated
              }
            ])
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, workitems: [aj_workitem_1])

      assert expected_state === calibration.state
      assert [aj_workitem_2] === calibration.to_withdraw
    end
  end

  describe "calibrate after complete" do
    import ColouredFlow.Notation.Colset

    use ColouredFlow.DefinitionHelpers

    alias ColouredFlow.Enactment.Occurrence

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #
    #   i((input))
    #   m((merge))
    #   o((output))
    #
    #   b1[branch_1]
    #   b2[branch_2]
    #   tm[thread_merge]
    #
    #   i --{1,x}--> b1
    #   i --{2,x}--> b2
    #   b1 & b2 --{1,x}--> m
    #   m --{2,1}--> tm
    #   tm --{1,1}--> o
    # ```

    @cpnet %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "merge", colour_set: :int},
        %Place{name: "output", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "branch_1", guard: nil},
        %Transition{name: "branch_2", guard: nil},
        %Transition{name: "thread_merge", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "branch_1",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "branch_2",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "branch_1",
          place: "merge",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "branch_2",
          place: "merge",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "thread_merge",
          place: "merge",
          orientation: :p_to_t,
          expression: "bind {2, 1}"
        ),
        build_arc!(
          transition: "thread_merge",
          place: "output",
          orientation: :t_to_p,
          expression: "{1, 1}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }

    test "produces no workitems when no new binding_elements enabled" do
      enactment_id = Ecto.UUID.generate()

      b2_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_2",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[2**1]}
          ]
        }
      }

      occurrence = %Occurrence{
        binding_element: b2_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~b[1]}]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 1,
        markings: to_map([%Marking{place: "merge", tokens: ~b[1]}]),
        workitems: to_map([])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete, cpnet: @cpnet, occurrences: [occurrence])

      assert [] === calibration.to_produce
    end

    test "produces new workitems when there is some live workitems at the transition" do
      enactment_id = Ecto.UUID.generate()

      b1_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      tm_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "thread_merge",
          binding: [],
          to_consume: [
            %Marking{place: "merge", tokens: ~b[2**1]}
          ]
        }
      }

      occurrence = %Occurrence{
        binding_element: b1_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~b[1]}]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 1,
        markings: to_map([%Marking{place: "merge", tokens: ~b[3**1]}]),
        workitems: to_map([tm_workitem])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete, cpnet: @cpnet, occurrences: [occurrence])

      assert [] === calibration.to_produce
    end

    test "completes mulitple workitems and produces new workitems for mulitple transitions" do
      enactment_id = Ecto.UUID.generate()

      b1_workitem_1 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      b1_workitem_2 = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      b1_occurrence_1 = %Occurrence{
        binding_element: b1_workitem_1.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~b[1]}]
      }

      b1_occurrence_2 = %Occurrence{
        binding_element: b1_workitem_2.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~b[1]}]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 2,
        markings:
          to_map([
            %Marking{place: "merge", tokens: ~b[2**1]}
          ]),
        workitems: to_map([])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: @cpnet,
          occurrences: [b1_occurrence_1, b1_occurrence_2]
        )

      assert [
               %BindingElement{
                 transition: "thread_merge",
                 binding: [],
                 to_consume: [%Marking{place: "merge", tokens: ~b[2**1]}]
               }
             ] === calibration.to_produce
    end

    test "produces new workitems for one transition" do
      enactment_id = Ecto.UUID.generate()

      b1_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "branch_1",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      b1_occurrence = %Occurrence{
        binding_element: b1_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "merge", tokens: ~b[1]}]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 1,
        markings: to_map([%Marking{place: "merge", tokens: ~b[2**1]}]),
        workitems: to_map([])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: @cpnet,
          occurrences: [b1_occurrence]
        )

      assert [
               %BindingElement{
                 transition: "thread_merge",
                 binding: [],
                 to_consume: [%Marking{place: "merge", tokens: ~b[2**1]}]
               }
             ] === calibration.to_produce
    end

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #
    #   %% ~b[1]
    #   i((input))
    #   p((place))
    #   o1((output_1))
    #   o2((output_2))
    #
    #   pt[pass_through]
    #   dc1[deferred_choice_1]
    #   dc2[deferred_choice_2]
    #
    #   i --{1,x}--> pt
    #   pt --{1,x}--> p
    #   p --{1,x}--> dc1 & dc2
    #   dc1 --{1,x}--> o1
    #   dc2 --{1,x}--> o2
    @cpnet %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "place", colour_set: :int},
        %Place{name: "output_1", colour_set: :int},
        %Place{name: "output_2", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "pass_through", guard: nil},
        %Transition{name: "deferred_choice_1", guard: nil},
        %Transition{name: "deferred_choice_2", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "pass_through",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through",
          place: "place",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_1",
          place: "place",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_2",
          place: "place",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_1",
          place: "output_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "deferred_choice_2",
          place: "output_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }

    test "produces new workitems for mulitple transitions" do
      enactment_id = Ecto.UUID.generate()

      pt_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "pass_through",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      pt_occurrence = %Occurrence{
        binding_element: pt_workitem.binding_element,
        free_binding: [],
        to_produce: [%Marking{place: "place", tokens: ~b[1]}]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 1,
        markings: to_map([%Marking{place: "place", tokens: ~b[1]}]),
        workitems: to_map([])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: @cpnet,
          occurrences: [pt_occurrence]
        )

      assert [
               %BindingElement{
                 transition: "deferred_choice_1",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place", tokens: ~b[1]}]
               },
               %BindingElement{
                 transition: "deferred_choice_2",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place", tokens: ~b[1]}]
               }
             ] === calibration.to_produce
    end

    # ```mermaid
    # flowchart TB
    #   %% colset int() :: integer()
    #
    #   %% ~b[1]
    #   i((input))
    #   p1((place_1))
    #   p2((place_2))
    #   o1((output_1))
    #   o2((output_2))
    #
    #   ps[parallel_split]
    #   pt1[pass_through_1]
    #   pt2[pass_through_2]
    #
    #   i --{1,x}--> ps
    #   ps --{1,x}--> p1 & p2
    #   p1 --{1,x}--> pt1
    #   p2 --{1,x}--> pt2
    #   pt1 --{1,x}--> o1
    #   pt2 --{1,x}--> o2
    @cpnet %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer())
      ],
      places: [
        %Place{name: "input", colour_set: :int},
        %Place{name: "place_1", colour_set: :int},
        %Place{name: "place_2", colour_set: :int},
        %Place{name: "output_1", colour_set: :int},
        %Place{name: "output_2", colour_set: :int}
      ],
      transitions: [
        %Transition{name: "parallel_split", guard: nil},
        %Transition{name: "pass_through_1", guard: nil},
        %Transition{name: "pass_through_2", guard: nil}
      ],
      arcs: [
        build_arc!(
          transition: "parallel_split",
          place: "input",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "parallel_split",
          place: "place_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "parallel_split",
          place: "place_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "pass_through_1",
          place: "place_1",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through_2",
          place: "place_2",
          orientation: :p_to_t,
          expression: "bind {1, x}"
        ),
        build_arc!(
          transition: "pass_through_1",
          place: "output_1",
          orientation: :t_to_p,
          expression: "{1, x}"
        ),
        build_arc!(
          transition: "pass_through_2",
          place: "output_2",
          orientation: :t_to_p,
          expression: "{1, x}"
        )
      ],
      variables: [
        %Variable{name: :x, colour_set: :int}
      ]
    }

    test "produces new workitems into mulitple places for mulitple transitions" do
      enactment_id = Ecto.UUID.generate()

      ps_workitem = %Enactment.Workitem{
        id: Ecto.UUID.generate(),
        state: :started,
        binding_element: %BindingElement{
          transition: "parallel_split",
          binding: [x: 1],
          to_consume: [
            %Marking{place: "input", tokens: ~b[1]}
          ]
        }
      }

      ps_occurrence = %Occurrence{
        binding_element: ps_workitem.binding_element,
        free_binding: [],
        to_produce: [
          %Marking{place: "place_1", tokens: ~b[1]},
          %Marking{place: "place_2", tokens: ~b[1]}
        ]
      }

      state = %Enactment{
        enactment_id: enactment_id,
        version: 0,
        markings:
          to_map([
            %Marking{place: "place_1", tokens: ~b[1]},
            %Marking{place: "place_2", tokens: ~b[1]}
          ]),
        workitems: to_map([])
      }

      calibration =
        WorkitemCalibration.calibrate(state, :complete,
          cpnet: @cpnet,
          occurrences: [ps_occurrence]
        )

      assert [
               %BindingElement{
                 transition: "pass_through_1",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place_1", tokens: ~b[1]}]
               },
               %BindingElement{
                 transition: "pass_through_2",
                 binding: [x: 1],
                 to_consume: [%Marking{place: "place_2", tokens: ~b[1]}]
               }
             ] === calibration.to_produce
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
