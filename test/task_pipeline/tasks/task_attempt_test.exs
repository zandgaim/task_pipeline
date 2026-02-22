defmodule TaskPipeline.Tasks.TaskAttemptTest do
  use ExUnit.Case, async: true

  alias TaskPipeline.Tasks.TaskAttempt

  describe "changeset/2" do
    test "valid when required fields present" do
      attrs = %{result: "ok", task_id: 1}
      changeset = TaskAttempt.changeset(%TaskAttempt{}, attrs)
      assert changeset.valid?
    end

    test "invalid when missing result" do
      attrs = %{task_id: 1}
      changeset = TaskAttempt.changeset(%TaskAttempt{}, attrs)
      refute changeset.valid?
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :result, 0)
    end

    test "invalid when missing task_id" do
      attrs = %{result: "ok"}
      changeset = TaskAttempt.changeset(%TaskAttempt{}, attrs)
      refute changeset.valid?
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :task_id, 0)
    end
  end
end
