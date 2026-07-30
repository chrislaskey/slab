defmodule Demo.Repo.Migrations.CreateOrganizationsAndProducts do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:products) do
      add :name, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:user_id])

    alter table(:users) do
      add :organization_id, references(:organizations, on_delete: :nilify_all)
    end
  end
end
