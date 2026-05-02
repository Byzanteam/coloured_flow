defmodule ColouredFlow.Validators.Definition.FunctionsValidatorTest do
  use ExUnit.Case, async: true

  use ColouredFlow.DefinitionHelpers
  import ColouredFlow.Notation.Colset

  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Validators.Definition.FunctionsValidator
  alias ColouredFlow.Validators.Exceptions.MissingColourSetError
  alias ColouredFlow.Validators.Exceptions.UniqueNameViolationError

  setup do
    cpnet = %ColouredPetriNet{
      colour_sets: [
        colset(int() :: integer()),
        colset(user() :: %{name: binary(), age: int()})
      ],
      places: [],
      transitions: [],
      arcs: [],
      variables: [],
      functions: []
    }

    [cpnet: cpnet]
  end

  describe "happy path" do
    test "passes when there are no functions", %{cpnet: cpnet} do
      assert {:ok, ^cpnet} = FunctionsValidator.validate(cpnet)
    end

    test "passes when all procedures have primitive result descrs", %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :add,
              expression: Expression.build!("x + y"),
              result: {:integer, []}
            },
            %Procedure{
              name: :greet,
              expression: Expression.build!(~S|"hello"|),
              result: {:binary, []}
            },
            %Procedure{
              name: :truthy?,
              expression: Expression.build!("true"),
              result: {:boolean, []}
            }
          ]
      }

      assert {:ok, ^cpnet} = FunctionsValidator.validate(cpnet)
    end

    test "passes when result descr is a deeply nested composite of primitives", %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :nested,
              expression: Expression.build!("[{1, [2.0]}]"),
              result:
                {:list,
                 {:tuple,
                  [
                    {:integer, []},
                    {:list, {:float, []}}
                  ]}}
            },
            %Procedure{
              name: :map_result,
              expression: Expression.build!("%{a: 1, b: 2.0}"),
              result: {:map, %{a: {:integer, []}, b: {:float, []}}}
            },
            %Procedure{
              name: :colour_choice,
              expression: Expression.build!(":red"),
              result: {:enum, [:red, :green, :blue]}
            },
            %Procedure{
              name: :tagged,
              expression: Expression.build!("{:ok, 1}"),
              result: {:union, %{ok: {:integer, []}, err: {:binary, []}}}
            }
          ]
      }

      assert {:ok, ^cpnet} = FunctionsValidator.validate(cpnet)
    end
  end

  describe "duplicate procedure names" do
    test "fails with UniqueNameViolationError using :function scope", %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :add,
              expression: Expression.build!("x + y"),
              result: {:integer, []}
            },
            %Procedure{
              name: :add,
              expression: Expression.build!("x + y + 1"),
              result: {:integer, []}
            }
          ]
      }

      assert {
               :error,
               %UniqueNameViolationError{scope: :function, name: :add}
             } = FunctionsValidator.validate(cpnet)
    end
  end

  describe "result descrs must be fully resolved" do
    test "fails with MissingColourSetError when result references unknown name",
         %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :is_odd,
              expression: Expression.build!("rem(x, 2) == 1"),
              # ":bool" is not declared in cpnet.colour_sets
              result: {:bool, []}
            }
          ]
      }

      assert {:error, %MissingColourSetError{colour_set: :bool} = error} =
               FunctionsValidator.validate(cpnet)

      message = Exception.message(error)
      assert message =~ "is_odd"
      assert message =~ "bool"
    end

    test "fails when an inner leaf of a deeply nested composite is unresolved",
         %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :produce_pairs,
              expression: Expression.build!("[]"),
              result:
                {:list,
                 {:tuple,
                  [
                    {:integer, []},
                    # ":ghost" is not declared
                    {:list, {:ghost, []}}
                  ]}}
            }
          ]
      }

      assert {:error, %MissingColourSetError{colour_set: :ghost} = error} =
               FunctionsValidator.validate(cpnet)

      message = Exception.message(error)
      assert message =~ "produce_pairs"
      assert message =~ "ghost"
    end

    test "fails when an inner leaf of a map descr is unresolved", %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :build_user,
              expression: Expression.build!("%{name: \"alice\", age: 21}"),
              result:
                {:map,
                 %{
                   name: {:binary, []},
                   age: {:phantom_int, []}
                 }}
            }
          ]
      }

      assert {:error, %MissingColourSetError{colour_set: :phantom_int} = error} =
               FunctionsValidator.validate(cpnet)

      message = Exception.message(error)
      assert message =~ "build_user"
      assert message =~ "phantom_int"
    end

    test "fails when a union arm is unresolved", %{cpnet: cpnet} do
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :tagged,
              expression: Expression.build!("{:ok, 1}"),
              result:
                {:union,
                 %{
                   ok: {:integer, []},
                   err: {:missing_type, []}
                 }}
            }
          ]
      }

      assert {:error, %MissingColourSetError{colour_set: :missing_type} = error} =
               FunctionsValidator.validate(cpnet)

      assert Exception.message(error) =~ "tagged"
    end

    test "passes when nested composite leaves all resolve to declared colour sets",
         %{cpnet: cpnet} do
      # `:int` and `:user` are declared in setup
      cpnet = %{
        cpnet
        | functions: [
            %Procedure{
              name: :user_list,
              expression: Expression.build!("[]"),
              result: {:list, {:user, []}}
            },
            %Procedure{
              name: :wrap_int,
              expression: Expression.build!("{:ok, 1}"),
              result: {:union, %{ok: {:int, []}, err: {:binary, []}}}
            }
          ]
      }

      assert {:ok, ^cpnet} = FunctionsValidator.validate(cpnet)
    end
  end
end
