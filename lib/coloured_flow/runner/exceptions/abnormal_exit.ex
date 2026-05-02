defmodule ColouredFlow.Runner.Exceptions.AbnormalExit do
  @moduledoc """
  Records an abnormal `terminate/2` exit reason. Wraps the underlying cause as an
  Elixir `Exception.t()` for uniform persistence.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :cause, Exception.t()
  end

  @impl Exception
  def exception(arguments), do: struct!(__MODULE__, arguments)

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "Enactment #{inspect(exception.enactment_id)} terminated abnormally: " <>
      Exception.message(exception.cause)
  end

  @doc """
  Build an `AbnormalExit` from the raw `terminate/2` reason.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec from_exit_reason(Storage.enactment_id(), term()) :: t()
  def from_exit_reason(enactment_id, reason) do
    %__MODULE__{enactment_id: enactment_id, cause: normalize(reason)}
  end

  defp normalize({exception, stacktrace})
       when is_exception(exception) and is_list(stacktrace),
       do: exception

  defp normalize(reason) when is_exception(reason), do: reason

  defp normalize(reason),
    do: RuntimeError.exception(Exception.format_exit(reason))
end
