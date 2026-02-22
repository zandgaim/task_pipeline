
# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     TaskPipeline.Repo.insert!(%TaskPipeline.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias TaskPipeline.Repo
alias TaskPipeline.Tasks.Task

tasks = [
	%{
		title: "Import users",
		type: :import,
		priority: :high,
		payload: %{source: "users.csv"},
		max_attempts: 3,
		status: :queued
	},
	%{
		title: "Export sales report",
		type: :export,
		priority: :normal,
		payload: %{destination: "sales_report.xlsx"},
		max_attempts: 3,
		status: :queued
	},
	%{
		title: "Generate monthly report",
		type: :report,
		priority: :critical,
		payload: %{month: "2026-02"},
		max_attempts: 5,
		status: :queued
	},
	%{
		title: "Cleanup old logs",
		type: :cleanup,
		priority: :low,
		payload: %{older_than_days: 30},
		max_attempts: 2,
		status: :queued
	},
	%{
		title: "Import products",
		type: :import,
		priority: :normal,
		payload: %{source: "products.json"},
		max_attempts: 4,
		status: :queued
	},
	%{
		title: "Export inventory",
		type: :export,
		priority: :high,
		payload: %{destination: "inventory.csv"},
		max_attempts: 3,
		status: :queued
	},
	%{
		title: "Generate weekly summary",
		type: :report,
		priority: :normal,
		payload: %{week: "2026-W08"},
		max_attempts: 2,
		status: :queued
	},
	%{
		title: "Cleanup temp files",
		type: :cleanup,
		priority: :critical,
		payload: %{folder: "/tmp", older_than_days: 7},
		max_attempts: 1,
		status: :queued
	},
	%{
		title: "Import customer feedback",
		type: :import,
		priority: :low,
		payload: %{source: "feedback.xml"},
		max_attempts: 2,
		status: :queued
	},
	%{
		title: "Export error logs",
		type: :export,
		priority: :critical,
		payload: %{destination: "error_logs.txt"},
		max_attempts: 5,
		status: :queued
	}
]

for attrs <- tasks do
	%Task{}
	|> Task.changeset(attrs)
	|> Repo.insert!()
end
