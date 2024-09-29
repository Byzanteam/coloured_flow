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
        enactment_id: Ecto.UUID.generate(),
        markings: [],
        workitems: []
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
        markings: [
          %Marking{place: "input", tokens: ~b[2**1]}
        ],
        workitems: []
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
        markings: [
          %Marking{place: "input", tokens: ~b[2**1]}
        ],
        workitems: [
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
        ]
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
        markings: [
          %Marking{place: "input", tokens: ~b[]}
        ],
        workitems: [
          workitem
        ]
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: []} === calibration.state
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
        markings: [
          %Marking{place: "input", tokens: ~b[1]}
        ],
        workitems: [
          workitem
        ]
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: []} === calibration.state
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
        markings: [
          %Marking{place: "input1", tokens: ~b[1]},
          %Marking{place: "input2", tokens: ~b[1]}
        ],
        workitems: [
          workitem
        ]
      }

      calibration = WorkitemCalibration.initial_calibrate(state, cpnet)

      assert %{state | workitems: []} === calibration.state
      assert [workitem] === calibration.to_withdraw
      assert ~b[] === calibration.to_produce
    end
  end

  describe "calibrate after allocate" do
    # ```mermad
    # flowchart LR
    #   i((input))
    #   o((output))
    #   pt1[pass_through_1]
    #   pt2[pass_through_2]
    #   i --> pt1 & pt2 --> o
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
        markings: [
          %Marking{place: "input", tokens: ~b[3**1]}
        ],
        workitems: [
          %Enactment.Workitem{
            pt1_workitem_1
            | state: :allocated
          },
          pt1_workitem_2,
          pt1_workitem_3,
          pt2_workitem
        ]
      }

      expected_state = %Enactment{
        state
        | workitems: [
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :allocated
            },
            pt1_workitem_2,
            pt1_workitem_3,
            pt2_workitem
          ]
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [] === calibration.to_withdraw
    end

    # ```mermad
    # flowchart LR
    #   i((input))
    #   o((output))
    #   pt1[pass_through_1]
    #   pt2[pass_through_2]
    #   i --> pt1 & pt2 --> o
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
        markings: [
          %Marking{place: "input", tokens: ~b[2**1]}
        ],
        workitems: [
          %Enactment.Workitem{
            pt1_workitem_1
            | state: :allocated
          },
          pt1_workitem_2,
          pt2_workitem
        ]
      }

      expected_state = %Enactment{
        state
        | workitems: [
            %Enactment.Workitem{
              pt1_workitem_1
              | state: :allocated
            },
            pt1_workitem_2
          ]
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, [pt1_workitem_1])

      assert expected_state === calibration.state
      assert [pt2_workitem] === calibration.to_withdraw
    end

    # ```mermad
    # flowchart TB
    #   %% colset int() :: integer()
    #   i1((input1))
    #   i2((input2))
    #   i3((input3))
    #   o((output))
    #   join[And Join]
    #   i1 & i2 & i3 --> join --> o
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
        markings: [
          %Marking{place: "input1", tokens: ~b[2**1]},
          %Marking{place: "input2", tokens: ~b[1]},
          %Marking{place: "input3", tokens: ~b[1]}
        ],
        workitems: [
          %Enactment.Workitem{
            aj_workitem_1
            | state: :allocated
          },
          aj_workitem_2
        ]
      }

      expected_state = %Enactment{
        state
        | workitems: [
            %Enactment.Workitem{
              aj_workitem_1
              | state: :allocated
            }
          ]
      }

      calibration = WorkitemCalibration.calibrate(state, :allocate, [aj_workitem_1])

      assert expected_state === calibration.state
      assert [aj_workitem_2] === calibration.to_withdraw
    end
  end
end
