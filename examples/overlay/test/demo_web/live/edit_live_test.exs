defmodule DemoWeb.EditLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  defp insert_user do
    Demo.Repo.insert!(%Demo.Accounts.User{
      name: "Ada",
      email: "ada@example.com",
      role: :member,
      active: true
    })
  end

  defp row_params(user, overrides) do
    Map.merge(
      %{
        "row_id" => to_string(user.id),
        "name" => user.name,
        "email" => user.email,
        "role" => to_string(user.role),
        "active" => to_string(user.active)
      },
      overrides
    )
  end

  test "changing a value marks the row dirty and saving persists it", %{conn: conn} do
    user = insert_user()

    {:ok, view, html} = live(conn, "/edit")
    assert html =~ ~s(value="Ada")

    form = element(view, "#edit-users-row-#{user.id}")

    # The change event marks the row dirty — the save button lights up
    html = render_change(form, row_params(user, %{"name" => "Ada Lovelace"}))
    assert html =~ "text-cyan-600 hover:text-cyan-700"

    # Submit calls the LiveView's save_user/2, which writes via Repo.update
    html = render_submit(form, row_params(user, %{"name" => "Ada Lovelace"}))
    assert html =~ ~s(value="Ada Lovelace")
    assert Demo.Repo.get!(Demo.Accounts.User, user.id).name == "Ada Lovelace"
  end

  test "changeset errors render under the row and keep the edits", %{conn: conn} do
    user = insert_user()

    {:ok, view, _html} = live(conn, "/edit")

    form = element(view, "#edit-users-row-#{user.id}")
    html = render_submit(form, row_params(user, %{"email" => "not-an-email"}))

    assert html =~ "must contain @"
    assert html =~ ~s(value="not-an-email")
    assert Demo.Repo.get!(Demo.Accounts.User, user.id).email == "ada@example.com"
  end
end
