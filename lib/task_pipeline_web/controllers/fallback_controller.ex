defmodule TaskPipelineWeb.FallbackController do
  require Logger
  use TaskPipelineWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Resource not found"})
  end

  def call(conn, {:error, reason}) do
    Logger.error("Unexpected error occurred in controller", reason: inspect(reason))

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end
end
