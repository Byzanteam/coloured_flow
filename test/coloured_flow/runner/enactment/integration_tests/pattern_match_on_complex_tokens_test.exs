defmodule ColouredFlow.Runner.Enactment.IntegrationTests.PatternMatchOnComplexTokensTest do
  use ColouredFlow.RepoCase
  use ColouredFlow.RunnerHelpers

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.MultiSet

  setup do
    use ColouredFlow.DefinitionHelpers

    import ColouredFlow.Notation

    # ```mermaid
    # flowchart TB
    #   %% remove common ips from machine1 and machine2
    #   %% colset octal() :: integer()
    #   %% colset hex() :: binary()
    #   %% colset ipv4() :: {octal(), octal(), octal(), octal()}
    #   %% colset ipv6() :: {hex(), hex(), hex(), hex(), hex(), hex(), hex(), hex()}
    #   %% colset ip() :: {:v4, ipv4()} | {:v6, ipv6()}
    #
    #   m1((machine1<br>::ip::))
    #   m2((machine2<br>::ip::))
    #   ov4((output_ipv4<br>::ip4::))
    #   ov6((output_ipv4<br>::ipv6::))
    #
    #   mv4[merge_ipv4]
    #   mv6[merge_ipv6]
    #
    #   m1--bind {1, {:v4, {o1, o2, o3, o4}}}-->mv4
    #   m2 --bind {1, {:v4, {o1, o2, o3, o4}}}-->mv4
    #   m1--bind {1, {:v6, {x1, x2, x3, x4, x5, x6, x7, x8}}}-->mv6
    #   m2 --bind {1, {:v6, {x1, x2, x3, x4, x5, x6, x7, x8}}}-->mv6
    #   mv4 --{1 {o1, o2, o3, o4}}--> ov4
    #   mv6 --{1, {x1, x2, x3, x4, x5, x6, x7, x8}}--> ov6
    # ```
    cpnet =
      %ColouredPetriNet{
        colour_sets: [
          colset(octal() :: integer()),
          colset(hex() :: binary()),
          colset(ipv4() :: {octal(), octal(), octal(), octal()}),
          colset(ipv6() :: {hex(), hex(), hex(), hex(), hex(), hex(), hex(), hex()}),
          colset(ip() :: {:v4, ipv4()} | {:v6, ipv6()})
        ],
        places: [
          %Place{name: "machine1", colour_set: :ip},
          %Place{name: "machine2", colour_set: :ip},
          %Place{name: "output_ipv4", colour_set: :ipv4},
          %Place{name: "output_ipv6", colour_set: :ipv6}
        ],
        transitions: [
          build_transition!(name: "merge_ipv4"),
          build_transition!(name: "merge_ipv6")
        ],
        arcs: [
          arc(merge_ipv4 <~ machine1 :: "bind {1, {:v4, {o1, o2, o3, o4}}}"),
          arc(merge_ipv4 <~ machine2 :: "bind {1, {:v4, {o1, o2, o3, o4}}}"),
          arc(merge_ipv4 ~> output_ipv4 :: "{1, {o1, o2, o3, o4}}"),
          arc(merge_ipv6 <~ machine1 :: "bind {1, {:v6, {x1, x2, x3, x4, x5, x6, x7, x8}}}"),
          arc(merge_ipv6 <~ machine2 :: "bind {1, {:v6, {x1, x2, x3, x4, x5, x6, x7, x8}}}"),
          arc(merge_ipv6 ~> output_ipv6 :: "{1, {x1, x2, x3, x4, x5, x6, x7, x8}}")
        ],
        # credo:disable-for-lines:3 Credo.Check.Warning.UnsafeToAtom
        variables:
          Enum.map(1..4, &%Variable{name: :"o#{&1}", colour_set: :octal}) ++
            Enum.map(1..8, &%Variable{name: :"x#{&1}", colour_set: :hex})
      }

    %{cpnet: cpnet}
  end

  describe "validates definition" do
    test "works", %{cpnet: cpnet} do
      assert {:ok, _cpnet} =
               cpnet
               |> ColouredFlow.Builder.build()
               |> ColouredFlow.Validators.run()
    end
  end

  describe "pattern match" do
    setup :setup_flow
    setup :setup_enactment
    setup :start_enactment

    @tag initial_markings: [
           %Marking{
             place: "machine1",
             tokens:
               MultiSet.new([
                 {:v4, {0, 0, 0, 0}},
                 {:v4, {1, 1, 1, 1}},
                 {:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}},
                 {:v6, {"1", "1", "1", "1", "1", "1", "1", "1"}}
               ])
           },
           %Marking{
             place: "machine2",
             tokens:
               MultiSet.new([
                 {:v4, {0, 0, 0, 0}},
                 {:v4, {2, 2, 2, 2}},
                 {:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}},
                 {:v6, {"2", "2", "2", "2", "2", "2", "2", "2"}}
               ])
           }
         ]
    test "works", %{enactment_server: enactment_server} do
      assert [
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "merge_ipv4",
                   binding: [o1: 0, o2: 0, o3: 0, o4: 0],
                   to_consume: to_consume_v4
                 }
               } = workitem_v4,
               %Enactment.Workitem{
                 state: :enabled,
                 binding_element: %BindingElement{
                   transition: "merge_ipv6",
                   binding: [
                     x1: "0",
                     x2: "0",
                     x3: "0",
                     x4: "0",
                     x5: "0",
                     x6: "0",
                     x7: "0",
                     x8: "0"
                   ],
                   to_consume: to_consume_v6
                 }
               } = workitem_v6
             ] = get_enactment_workitems(enactment_server)

      assert [
               %Marking{
                 place: "machine1",
                 tokens: MultiSet.new([{:v4, {0, 0, 0, 0}}])
               },
               %Marking{
                 place: "machine2",
                 tokens: MultiSet.new([{:v4, {0, 0, 0, 0}}])
               }
             ] === to_consume_v4

      assert [
               %Marking{
                 place: "machine1",
                 tokens: MultiSet.new([{:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}}])
               },
               %Marking{
                 place: "machine2",
                 tokens: MultiSet.new([{:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}}])
               }
             ] === to_consume_v6

      {:ok, _workitems} =
        GenServer.call(
          enactment_server,
          {:complete_workitems, %{workitem_v4.id => []}}
        )

      wait_enactment_requests_handled!(enactment_server)

      assert Process.alive?(enactment_server)

      assert %Schemas.Workitem{state: :completed} =
               Repo.get!(Schemas.Workitem, workitem_v4.id)

      assert [workitem_v6] === get_enactment_workitems(enactment_server)

      assert [
               %Marking{
                 place: "machine1",
                 tokens:
                   ColouredFlow.MultiSet.new([
                     {:v4, {1, 1, 1, 1}},
                     {:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}},
                     {:v6, {"1", "1", "1", "1", "1", "1", "1", "1"}}
                   ])
               },
               %Marking{
                 place: "machine2",
                 tokens:
                   ColouredFlow.MultiSet.new([
                     {:v4, {2, 2, 2, 2}},
                     {:v6, {"0", "0", "0", "0", "0", "0", "0", "0"}},
                     {:v6, {"2", "2", "2", "2", "2", "2", "2", "2"}}
                   ])
               },
               %Marking{
                 place: "output_ipv4",
                 tokens: ColouredFlow.MultiSet.new([{0, 0, 0, 0}])
               }
             ] === get_enactment_markings(enactment_server)
    end
  end
end
