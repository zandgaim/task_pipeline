# priv/repo/migrations/XXXX_add_tasks_and_attempts.exs
defmodule TaskPipeline.Repo.Migrations.AddTasksAndAttempts do
  use Ecto.Migration

  def change do
    # Типи ENUM (специфічно для PostgreSQL)
    execute "CREATE TYPE task_type AS ENUM ('import', 'export', 'report', 'cleanup')",
            "DROP TYPE task_type"

    execute "CREATE TYPE task_priority AS ENUM ('low', 'normal', 'high', 'critical')",
            "DROP TYPE task_priority"

    execute "CREATE TYPE task_status AS ENUM ('queued', 'processing', 'completed', 'failed')",
            "DROP TYPE task_status"

    create table(:tasks) do
      add :title, :string, null: false
      add :type, :task_type, null: false
      add :priority, :task_priority, null: false
      add :payload, :map, null: false
      add :max_attempts, :integer, default: 3, null: false
      add :status, :task_status, default: "queued", null: false

      timestamps()
    end

    # Індекси для оптимізації [cite: 75]
    create index(:tasks, [:status])
    create index(:tasks, [:priority, :inserted_at])
  end
end
