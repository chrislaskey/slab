defmodule Demo.Accounts.Product do
  use Ecto.Schema

  schema "products" do
    field :name, :string

    belongs_to :user, Demo.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
