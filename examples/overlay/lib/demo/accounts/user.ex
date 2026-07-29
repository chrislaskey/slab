defmodule Demo.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member, :guest]
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :active])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/, message: "must contain @")
  end
end
