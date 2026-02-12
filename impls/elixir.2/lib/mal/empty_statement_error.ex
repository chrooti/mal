defmodule Mal.EmptyStatementError do
  defexception []

  @impl true
  def message(_), do: "Empty statement"
end
