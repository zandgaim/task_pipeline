defmodule TaskPipeline.Tasks.TaskAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_attempts" do
    field :result, :string
    belongs_to :task, TaskPipeline.Tasks.Task

    timestamps(updated_at: false)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:result, :task_id])
    |> validate_required([:result, :task_id])
  end
end
