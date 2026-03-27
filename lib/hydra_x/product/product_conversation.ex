defmodule HydraX.Product.ProductConversation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active archived)

  schema "product_conversations" do
    field :persona, :string
    field :title, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    belongs_to :hydra_conversation, HydraX.Runtime.Conversation

    has_many :product_messages, HydraX.Product.ProductMessage

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:project_id, :hydra_conversation_id, :persona, :title, :status, :metadata])
    |> validate_required([:project_id, :hydra_conversation_id, :persona, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:hydra_conversation_id)
    |> unique_constraint(:hydra_conversation_id)
  end
end
