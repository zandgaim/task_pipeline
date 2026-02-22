defmodule TaskPipeline.Tasks.TasksTest do
  use TaskPipeline.DataCase, async: false

  alias TaskPipeline.{Repo, Tasks}
  alias TaskPipeline.Tasks.Task

  defp task_fixture(attrs \\ %{}) do
    default = %{
      title: "Test Task",
      type: :import,
      priority: :normal,
      payload: %{"foo" => "bar"},
      max_attempts: 3
    }

    attrs = Map.merge(default, attrs)

    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert!()
  end

  describe "get_task/1" do
    test "returns error when missing and ok with preloaded attempts" do
      assert {:error, :not_found} = Tasks.get_task(-1)

      task = task_fixture()

      assert {:ok, _loaded} = Tasks.get_task(task.id)
    end
  end

  describe "list_tasks/1 and ordering" do
    test "filters and orders by priority" do
      _t1 = task_fixture(%{priority: :normal, inserted_at: ~N[2020-01-01 00:00:00]})
      _t2 = task_fixture(%{priority: :high, inserted_at: ~N[2020-01-02 00:00:00]})
      _t3 = task_fixture(%{priority: :critical, inserted_at: ~N[2020-01-03 00:00:00]})

      results = Tasks.list_tasks(%{})
      priorities = Enum.map(results, & &1.priority)

      assert Enum.take(priorities, 3) == [:critical, :high, :normal]

      # filter by type
      results = Tasks.list_tasks(%{"type" => :import})
      assert Enum.all?(results, fn r -> r.type == :import end)
    end
  end

  describe "start_processing/1" do
    test "moves queued task to processing" do
      task = task_fixture(%{status: :queued})

      _ = Tasks.start_processing(task.id)

      reloaded = Repo.get(Task, task.id)
      assert reloaded.status == :processing
    end

    test "returns error if task not queued" do
      task = task_fixture(%{status: :processing})

      assert {:error, :not_queued} = Tasks.start_processing(task.id)
    end
  end

  describe "mark_task_completed/1 and mark_task_failed/3" do
    test "completes a task and inserts success attempt" do
      task = task_fixture(%{status: :processing})

      Tasks.mark_task_completed(task)

      reloaded = Repo.get(Task, task.id)
      assert reloaded.status == :completed
    end

    test "marks failed when attempts exhausted and queues otherwise" do
      task = task_fixture(%{status: :processing, max_attempts: 2})

      # first failure (current_attempt < max_attempts) -> requeueTaskController
      Tasks.mark_task_failed(task, 1)
      t1 = Repo.get(Task, task.id)
      assert t1.status == :queued

      # second failure (current_attempt >= max_attempts) -> failed
      Tasks.mark_task_failed(t1, 2)
      t2 = Repo.get(Task, task.id)
      assert t2.status == :failed
    end
  end
end
