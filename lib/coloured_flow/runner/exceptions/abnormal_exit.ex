defmodule ColouredFlow.Runner.Exceptions.AbnormalExit do
  @moduledoc """
  Records an abnormal `terminate/2` exit reason as a `:crash` log entry. Used by
  the consecutive-crash circuit breaker. The enactment row stays `:running`;
  recovery is attempted on the next supervisor restart.
  """

  use TypedStructor

  typed_structor definer: :defexception, enforce: true do
    # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
    field :reason, term()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{reason: reason}) do
    "Enactment terminated abnormally: #{inspect(reason)}"
  end
end
