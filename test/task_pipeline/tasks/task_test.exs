defmodule TaskPipeline.Tasks.TaskTest do
  use ExUnit.Case, async: true

  alias TaskPipeline.Tasks.Task

  describe "changeset/2" do
    test "valid when required fields present" do
      attrs = %{
        title: "Import users",
        type: :import,
        priority: :normal,
        payload: %{"source" => "csv"},
        max_attempts: 5
      }

      changeset = Task.changeset(%Task{}, attrs)
      assert changeset.valid?
    end

    test "invalid when missing required fields" do
      attrs = %{}
      changeset = Task.changeset(%Task{}, attrs)
      refute changeset.valid?
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :title, 0)
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :type, 0)
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :priority, 0)
      assert {_, {"can't be blank", _}} = List.keyfind(changeset.errors, :payload, 0)
    end

    test "invalid when max_attempts is non-positive" do
      attrs = %{
        title: "T",
        type: :export,
        priority: :low,
        payload: %{},
        max_attempts: 0
      }

      changeset = Task.changeset(%Task{}, attrs)
      refute changeset.valid?

      assert {_, {"must be greater than %{number}", _}} =
               List.keyfind(changeset.errors, :max_attempts, 0)
    end

    test "invalid when enum values are invalid" do
      attrs = %{
        title: "T",
        type: :unknown_type,
        priority: :unknown_priority,
        payload: %{}
      }

      changeset = Task.changeset(%Task{}, attrs)
      refute changeset.valid?
      assert {_, {"is invalid", _}} = List.keyfind(changeset.errors, :type, 0)
      assert {_, {"is invalid", _}} = List.keyfind(changeset.errors, :priority, 0)
    end
  end
end
