defmodule TaskPipeline.Workers.TaskWorker do
  use Oban.Worker,
    # Default queue, overridden dynamically upon enqueue
    queue: :normal,
    # We will dynamically override this per-job based on the Task model
    max_attempts: 3,
    unique: [
      # Prevents the exact same task from being enqueued concurrently
      fields: [:args],
      keys: [:task_id],
      states: [:available, :scheduled, :executing]
    ]

  alias TaskPipeline.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}, attempt: attempt}) do
    case Tasks.start_processing(task_id) do
      {:ok, task} ->
        sleep_duration(task.priority) |> Process.sleep()

        if should_fail?() do
          Tasks.mark_task_failed(task, attempt)
          {:error, "Simulated processing error"}
        else
          Tasks.mark_task_completed(task)
          :ok
        end

      {:error, :not_queued} ->
        {:cancel, "Task is not in queued state"}
    end
  end

  defp sleep_duration(priority) do
    case priority do
      :critical -> Enum.random(1_000..2_000)
      :high -> Enum.random(2_000..4_000)
      :normal -> Enum.random(4_000..6_000)
      :low -> Enum.random(6_000..8_000)
    end
  end

  defp should_fail? do
    Application.get_env(:task_pipeline, :worker_should_fail, fn ->
      Enum.random(1..100) <= 20
    end).()
  end
end
