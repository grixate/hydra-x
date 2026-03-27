defmodule HydraX.Product.ProductMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_messages" do
    field :role, :string
    field :content, :string
    field :citations, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :product_conversation, HydraX.Product.ProductConversation
    belongs_to :hydra_turn, HydraX.Runtime.Turn

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :product_conversation_id,
      :hydra_turn_id,
      :role,
      :content,
      :citations,
      :metadata
    ])
    |> validate_required([:product_conversation_id, :role, :content])
    |> foreign_key_constraint(:product_conversation_id)
    |> foreign_key_constraint(:hydra_turn_id)
  end
end
