defmodule HydraX.Ingest.Run do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(imported archived failed skipped)

  schema "hx_ingest_runs" do
    field :source_file, :string
    field :source_path, :string
    field :status, :string
    field :chunk_count, :integer, default: 0
    field :created_count, :integer, default: 0
    field :skipped_count, :integer, default: 0
    field :archived_count, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :agent_id,
      :source_file,
      :source_path,
      :status,
      :chunk_count,
      :created_count,
      :skipped_count,
      :archived_count,
      :metadata
    ])
    |> validate_required([:agent_id, :source_file, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:chunk_count, greater_than_or_equal_to: 0)
    |> validate_number(:created_count, greater_than_or_equal_to: 0)
    |> validate_number(:skipped_count, greater_than_or_equal_to: 0)
    |> validate_number(:archived_count, greater_than_or_equal_to: 0)
    |> assoc_constraint(:agent)
  end
end
