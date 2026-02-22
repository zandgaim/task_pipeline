defmodule TaskPipelineWeb.TaskController do
  use TaskPipelineWeb, :controller
  alias TaskPipeline.Tasks

  action_fallback TaskPipelineWeb.FallbackController

  def create(conn, %{"task" => task_params}) do
    with {:ok, task} <- Tasks.create_task(task_params) do
      conn
      |> put_status(:created)
      |> json(%{data: task})
    end
  end

  def index(conn, params) do
    tasks = Tasks.list_tasks(params)
    json(conn, %{data: tasks})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, task} <- Tasks.get_task(id) do
      json(conn, %{data: task})
    end
  end

  def summary(conn, _params) do
    counts = Tasks.get_summary()
    json(conn, counts)
  end
end
