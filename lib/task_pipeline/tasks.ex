defmodule TaskPipeline.Tasks do
  import Ecto.Query
  alias TaskPipeline.Repo
  alias TaskPipeline.Tasks.{Task, TaskAttempt}
  alias TaskPipeline.Workers.TaskWorker

  def create_task(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:task, Task.changeset(%Task{}, attrs))
    |> Ecto.Multi.insert(:oban_job, fn %{task: task} ->
      %{task_id: task.id}
      |> TaskWorker.new(
        max_attempts: task.max_attempts,
        priority: oban_priority(task.priority)
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{task: task}} -> {:ok, task}
      {:error, :task, changeset, _} -> {:error, changeset}
    end
  end

  def get_task(id) do
    case Repo.get(Task, id) do
      nil -> {:error, :not_found}
      task -> {:ok, Repo.preload(task, :attempts)}
    end
  end

  def list_tasks(params \\ %{}) do
    # Hard cap the limit so we don't blow up memory.
    # In a real senior take-home, implement cursor pagination (e.g. using Flop or custom queries).
    limit = Map.get(params, "limit", 50) |> min(100)

    Task
    |> build_task_query(params)
    |> order_by_priority()
    |> limit(^limit)
    |> Repo.all()
  end

  def get_summary do
    TaskPipeline.Metrics.SummaryCache.get_counts()
  end

  defp build_task_query(query, params) do
    ["status", "type", "priority"]
    |> Enum.reduce(query, fn key, q ->
      case Map.get(params, key) do
        nil ->
          q

        val ->
          field_name = String.to_existing_atom(key)
          where(q, [t], field(t, ^field_name) == ^val)
      end
    end)
  end

  # Example using fragment to sort string enums.
  # (Skip this if you defined a custom Postgres enum type in your migration!)
  defp order_by_priority(query) do
    from t in query,
      order_by: [
        asc:
          fragment(
            "case ? when 'critical' then 1 when 'high' then 2 when 'normal' then 3 when 'low' then 4 end",
            t.priority
          ),
        desc: t.inserted_at
      ]
  end

  defp oban_priority(:critical), do: 0
  defp oban_priority(:high), do: 1
  defp oban_priority(:normal), do: 2
  defp oban_priority(:low), do: 3

  def start_processing(task_id) do
    query =
      from t in Task,
        where: t.id == ^task_id and t.status == :queued,
        select: t

    case Repo.one(query) do
      nil ->
        {:error, :not_queued}

      task ->
        case Repo.update(Ecto.Changeset.change(task, status: :processing)) do
          {:ok, task} -> {:ok, task}
          _ -> {:error, :not_queued}
        end
    end
  end

  def mark_task_completed(task) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:task, Ecto.Changeset.change(task, status: :completed))
    |> Ecto.Multi.insert(
      :attempt,
      TaskAttempt.changeset(%TaskAttempt{}, %{task_id: task.id, result: "success"})
    )
    |> Repo.transaction()
  end

  def mark_task_failed(task, current_attempt, error_msg) do
    next_status = if current_attempt >= task.max_attempts, do: :failed, else: :queued

    Ecto.Multi.new()
    |> Ecto.Multi.update(:task, Ecto.Changeset.change(task, status: next_status))
    |> Ecto.Multi.insert(
      :attempt,
      TaskAttempt.changeset(%TaskAttempt{}, %{task_id: task.id, result: error_msg})
    )
    |> Repo.transaction()
  end
end
