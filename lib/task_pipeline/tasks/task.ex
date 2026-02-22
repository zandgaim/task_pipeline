defmodule TaskPipeline.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @type_enum [:import, :export, :report, :cleanup]
  @priority_enum [:low, :normal, :high, :critical]
  @status_enum [:queued, :processing, :completed, :failed]

  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :type,
             :priority,
             :payload,
             :max_attempts,
             :status,
             :inserted_at,
             :updated_at
           ]}
  schema "tasks" do
    field :title, :string
    field :type, Ecto.Enum, values: @type_enum
    field :priority, Ecto.Enum, values: @priority_enum
    field :payload, :map
    field :max_attempts, :integer, default: 3
    field :status, Ecto.Enum, values: @status_enum, default: :queued

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :type, :priority, :payload, :max_attempts, :status])
    |> validate_required([:title, :type, :priority, :payload])
    |> validate_number(:max_attempts, greater_than: 0)
  end
end
