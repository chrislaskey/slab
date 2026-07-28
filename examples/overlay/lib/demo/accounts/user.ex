defmodule Demo.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member, :guest]
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end
end
