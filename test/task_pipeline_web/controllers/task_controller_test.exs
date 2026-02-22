defmodule TaskPipelineWeb.TaskControllerTest do
  use TaskPipelineWeb.ConnCase, async: false

  alias TaskPipeline.Tasks

  describe "API /tasks endpoints" do
    setup do
      # Create a sample task in the DB for show/index tests
      {:ok, task} =
        Tasks.create_task(%{
          type: "export",
          title: "Test Task",
          priority: :normal,
          max_attempts: 3,
          status: :queued,
          payload: %{"foo" => "bar"}
        })

      %{task: task}
    end

    test "GET /api/tasks/summary returns counts", %{conn: conn} do
      conn = get(conn, "/api/tasks/summary")
      assert json_response(conn, 200)
      # optionally assert keys exist
      assert %{"queued" => _, "processing" => _, "completed" => _} = json_response(conn, 200)
    end

    test "GET /api/tasks returns list of tasks", %{conn: conn, task: task} do
      conn = get(conn, "/api/tasks")
      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.any?(data, &(&1["id"] == task.id))
    end

    test "GET /api/tasks/:id returns a task", %{conn: conn, task: task} do
      conn = get(conn, "/api/tasks/#{task.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == task.id
      assert data["title"] == "Test Task"
    end

    test "GET /api/tasks/:id returns 404 for missing task", %{conn: conn} do
      conn = get(conn, "/api/tasks/-1")
      assert %{"error" => "Resource not found"} = json_response(conn, 404)
    end

    test "POST /api/tasks creates a task", %{conn: conn} do
      task_params = %{
        "title" => "New Task",
        "type" => "export",
        "priority" => "normal",
        "max_attempts" => 3,
        "payload" => %{"data" => "xyz"}
      }

      conn = post(conn, "/api/tasks", %{"task" => task_params})
      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "New Task"
      assert data["type"] == "export"
    end

    test "POST /api/tasks returns 422 on invalid params", %{conn: conn} do
      # Missing required "type"
      task_params = %{
        "title" => "Bad Task",
        "priority" => "normal",
        "max_attempts" => 3
      }

      conn = post(conn, "/api/tasks", %{"task" => task_params})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end
end
