defmodule Demo.Accounts.Organization do
  use Ecto.Schema

  schema "organizations" do
    field :name, :string

    has_many :users, Demo.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
