defmodule TaskPipeline.Workers.TaskWorkerTest do
  use TaskPipeline.DataCase, async: false
  use Oban.Testing, repo: TaskPipeline.Repo

  alias TaskPipeline.Repo
  alias TaskPipeline.Tasks
  alias TaskPipeline.Tasks.Task
  alias TaskPipeline.Workers.TaskWorker
  alias TaskPipeline.Metrics.SummaryCache

  setup do
    SummaryCache.reset!()
    :ok
  end

  describe "success path" do
    test "marks task completed and inserts success attempt" do
      {:ok, task} =
        Tasks.create_task(%{
          title: "Test Task",
          payload: %{"data" => "test"},
          type: "import",
          priority: "normal",
          max_attempts: 3,
          status: :queued
        })

      job =
        Oban.Job
        |> where(args: ^%{"task_id" => task.id})
        |> Repo.one!()

      should_fail(false, fn ->
        assert :ok = perform_job(TaskWorker, job.args, attempt: 1, max_attempts: job.max_attempts)
      end)

      task = Repo.get!(Task, task.id) |> Repo.preload(:attempts)

      assert task.status == :completed
      assert Enum.any?(task.attempts, &(&1.result == "success"))

      counts = SummaryCache.get_counts()
      assert counts["queued"] == 0
      assert counts["completed"] == 1
    end
  end

  describe "retryable failure" do
    test "returns error and requeues task" do
      {:ok, task} =
        Tasks.create_task(%{
          title: "Test Task",
          payload: %{"data" => "test"},
          type: "export",
          priority: "normal",
          max_attempts: 3,
          status: :queued
        })

      job = build_job(TaskWorker, %{task_id: task.id}, attempt: 1)

      # Force failure

      should_fail(true, fn ->
        assert {:error, _} = perform_job(TaskWorker, job.args, attempt: 1)
      end)

      task = Repo.get!(Task, task.id)
      assert task.status == :queued

      counts = SummaryCache.get_counts()
      assert counts["queued"] == 1
    end
  end

  describe "retry exhaustion" do
    test "marks task failed when max attempts reached" do
      {:ok, task} =
        Tasks.create_task(%{
          title: "Test Task",
          payload: %{"data" => "test"},
          type: "import",
          priority: "normal",
          max_attempts: 1,
          status: :queued
        })

      job =
        Oban.Job
        |> where(args: ^%{"task_id" => task.id})
        |> Repo.one!()

      should_fail(true, fn ->
        assert {:error, _} =
                 perform_job(TaskWorker, job.args,
                   max_attempts: job.max_attempts,
                   attempt: job.attempt
                 )
      end)

      task = Repo.get!(Task, task.id)
      assert task.status == :failed

      counts = SummaryCache.get_counts()
      assert counts["processing"] == 0
      assert counts["failed"] == 1
    end
  end

  describe "not queued" do
    test "cancels job if task not queued" do
      task =
        Repo.insert!(%TaskPipeline.Tasks.Task{
          title: "Test Task",
          payload: %{"data" => "test"},
          type: :export,
          priority: :normal,
          max_attempts: 3,
          status: :processing
        })

      job = build_job(TaskWorker, %{task_id: task.id})

      should_fail(false, fn ->
        assert {:cancel, _} = perform_job(TaskWorker, job.args)
      end)

      counts = SummaryCache.get_counts()
      assert counts["processing"] == 0
      assert counts["failed"] == 1
    end
  end

  describe "missing task" do
    test "discards job if task does not exist" do
      job = build_job(TaskWorker, %{task_id: -1})

      assert {:cancel, _} = perform_job(TaskWorker, job.args)

      counts = SummaryCache.get_counts()
      assert counts["processing"] == 0
      assert counts["failed"] == 1
    end
  end

  defp should_fail(bool, fun) do
    Application.put_env(:task_pipeline, :worker_should_fail, fn -> bool end)
    fun.()
    Application.delete_env(:task_pipeline, :worker_should_fail)
  end
end
