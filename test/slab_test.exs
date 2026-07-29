defmodule SlabTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.Component
  import Phoenix.LiveViewTest

  doctest Slab

  defmodule User do
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: true}
    schema "users" do
      field(:name, :string)
      field(:active, :boolean)
      field(:role, Ecto.Enum, values: [:admin, :member, :guest])
      field(:inserted_at, :utc_datetime)
      field(:metadata, :map)
      field(:tags, {:array, :string})
    end
  end

  # Records every query it receives back to the test process and returns a
  # canned result, standing in for an Ecto.Repo.
  defmodule FakeRepo do
    def users do
      [
        %SlabTest.User{
          id: "0b937381-b621-4a3f-aa9a-a08e26f04b02",
          name: "Ada",
          active: true,
          inserted_at: ~U[2026-01-01 12:00:00Z]
        },
        %SlabTest.User{
          id: "594f52e6-936b-4c4f-bfe6-c6d52ce0d05d",
          name: "Grace",
          active: true,
          inserted_at: ~U[2026-01-02 12:00:00Z]
        },
        %SlabTest.User{
          id: "c02fbbdd-1f4d-441c-b641-baecda15a1f4",
          name: "Katherine",
          active: false,
          inserted_at: ~U[2026-01-03 12:00:00Z]
        }
      ]
    end

    def all(query) do
      send(self(), {:repo_all, query})
      users()
    end

    def aggregate(query, :count) do
      send(self(), {:repo_aggregate, query})
      42
    end
  end

  describe "table/1" do
    test "renders records with humanized column names" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data}>
              <:col field={:id} />
              <:col field={:first_name} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, first_name: "Ada"}, %{id: 2, first_name: "Grace"}]
        )

      assert html =~ "First Name"
      assert html =~ "Ada"
      assert html =~ "Grace"

      # The table always renders inside a bordered, shadowed card
      assert html =~ ~r{<section class="[^"]*border[^"]*shadow-sm[^"]*rounded-lg}
    end

    test "renders typed cells when a schema is given" do
      uuid = "0b937381-b621-4a3f-aa9a-a08e26f04b02"

      record = %User{
        id: uuid,
        name: "Ada",
        active: true,
        inserted_at: ~U[2026-01-01 12:00:00Z],
        metadata: %{"role" => "admin"},
        tags: ["one", "two"]
      }

      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} schema={SlabTest.User}>
              <:col field={:id} />
              <:col field={:name} />
              <:col field={:active} />
              <:col field={:inserted_at} />
              <:col field={:metadata} />
              <:col field={:tags} />
            </Slab.table>
            """
          end,
          data: [record]
        )

      # UUID truncated with full value in tooltip
      assert html =~ "0b937381"
      assert html =~ uuid

      # Boolean with icon
      assert html =~ "True"

      # Datetime with absolute and relative formats
      assert html =~ "Thu, 01 Jan 2026 12:00:00"
      assert html =~ "ago"

      # Map as codeblock
      assert html =~ "role"

      # Array of strings, one per line
      assert html =~ "one"
      assert html =~ "two"
    end

    test "renders slot bodies with the record via :let" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data}>
              <:col :let={user} field={:name}>{String.upcase(user.name)}</:col>
              <:col :let={user} label="Actions">Edit {user.name}</:col>
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )

      # Custom body overrides field rendering
      assert html =~ "ADA"

      # Virtual column with no field
      assert html =~ "Actions"
      assert html =~ "Edit Ada"
    end

    test "renders custom labels" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data}>
              <:col field={:name} label="Full Name" />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )

      assert html =~ "Full Name"
      refute html =~ ">Name<"
    end

    test "renders sortable headers as patch links with a direction indicator" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} uri={@uri} params={@params}>
              <:col field={:name} sortable />
              <:col field={:email} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada", email: "ada@example.com"}],
          uri: "https://example.com/users?sort=name&sort_direction=asc",
          params: %{"sort" => "name", "sort_direction" => "asc"}
        )

      # Sortable header is a patch link flipping the current ascending sort
      assert html =~ ~s(href="/users?sort=name&amp;sort_direction=desc")
      assert html =~ "data-phx-link"

      # chevron-up-outline icon path (ascending)
      assert html =~ "M4.5 15.75l7.5-7.5 7.5 7.5"

      # Non-sortable column renders as plain text
      refute html =~ ~s(sort=email)
    end

    test "does not render sort links without a uri" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data}>
              <:col field={:name} sortable />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )

      refute html =~ "data-phx-link"
      assert html =~ "Name"
    end

    test "renders checkboxes when checkable" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} checkable? uri={@uri}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}, %{id: 2, name: "Grace"}],
          uri: "https://example.com/users?checked[]=1"
        )

      assert html =~ "toggle-checkbox-for-all"
      assert html =~ "toggle-checkbox-for-row"
      assert html =~ ~s(name="checked_row")
    end

    test "does not render checkboxes without a uri" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} checkable?>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )

      refute html =~ "toggle-checkbox-for-row"
    end
  end

  describe "table/1 query mode" do
    test "fetches data through the repo and renders it with schema types" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" schema={SlabTest.User} repo={SlabTest.FakeRepo}>
              <:col field={:name} />
              <:col field={:active} />
            </Slab.table>
            """
          end,
          %{}
        )

      # No sort params, so the schema module passes through unmodified
      assert_received {:repo_all, SlabTest.User}

      assert html =~ "Ada"
      # Boolean rendered by field type, proving the schema hint is derived
      assert html =~ "True"
    end

    test "accepts an Ecto.Query and derives the schema from it" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" schema={@query} repo={SlabTest.FakeRepo}>
              <:col field={:active} />
            </Slab.table>
            """
          end,
          query: from(u in User, where: not is_nil(u.name))
        )

      assert_received {:repo_all, %Ecto.Query{wheres: [_where]}}
      assert html =~ "True"
    end

    test "applies sort params to the query when the field is sortable" do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table id="test-table" schema={SlabTest.User} repo={SlabTest.FakeRepo} uri={@uri} params={@params}>
            <:col field={:name} sortable />
          </Slab.table>
          """
        end,
        uri: "https://example.com/users?sort=name&sort_direction=desc",
        params: %{"sort" => "name", "sort_direction" => "desc"}
      )

      assert_received {:repo_all, %Ecto.Query{order_bys: [order_by]}}
      assert inspect(order_by.expr) =~ "desc"
    end

    test "ignores sort params for fields not declared sortable" do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table id="test-table" schema={SlabTest.User} repo={SlabTest.FakeRepo} uri={@uri} params={@params}>
            <:col field={:name} />
          </Slab.table>
          """
        end,
        uri: "https://example.com/users?sort=name&sort_direction=desc",
        params: %{"sort" => "name", "sort_direction" => "desc"}
      )

      # The queryable passes through untouched — no ORDER BY was compiled
      assert_received {:repo_all, SlabTest.User}
    end

    test "does not refetch when query inputs are unchanged" do
      assigns = %{
        id: "test-table",
        data: nil,
        schema: User,
        repo: FakeRepo,
        uri: nil,
        params: %{},
        checkable?: false,
        col: [%{field: :name}]
      }

      {:ok, socket} = Slab.Live.update(assigns, %Phoenix.LiveView.Socket{})
      assert_received {:repo_all, _query}

      {:ok, socket} = Slab.Live.update(assigns, socket)
      refute_received {:repo_all, _query}

      # Changing a query input triggers a refetch
      sorted = %{assigns | params: %{"sort" => "name"}, col: [%{field: :name, sortable: true}]}
      {:ok, _socket} = Slab.Live.update(sorted, socket)
      assert_received {:repo_all, _query}
    end

    test "falls back to the repo configured in the application environment" do
      Application.put_env(:slab, :repo, SlabTest.FakeRepo)
      on_exit(fn -> Application.delete_env(:slab, :repo) end)

      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" schema={SlabTest.User}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          %{}
        )

      assert_received {:repo_all, SlabTest.User}
      assert html =~ "Ada"
    end

    test "raises without data and schema" do
      assert_raise ArgumentError, ~r/requires either data/, fn ->
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table">
              <:col field={:name} />
            </Slab.table>
            """
          end,
          %{}
        )
      end
    end

    test "raises in query mode without a repo" do
      assert_raise ArgumentError, ~r/requires a repo/, fn ->
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" schema={SlabTest.User}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          %{}
        )
      end
    end

    test "raises when both data and repo are given" do
      assert_raise ArgumentError, ~r/both data and repo/, fn ->
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} repo={SlabTest.FakeRepo}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )
      end
    end
  end

  describe "table/1 filtering" do
    defp render_filter_table(params, col_opts) do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table
            id="test-table"
            schema={SlabTest.User}
            repo={SlabTest.FakeRepo}
            uri={@uri}
            params={@params}
          >
            <:col
              field={@col_opts[:field]}
              filterable={@col_opts[:filterable] || false}
              filter_query={@col_opts[:filter_query]}
            />
          </Slab.table>
          """
        end,
        uri: "https://example.com/users",
        params: params,
        col_opts: col_opts
      )
    end

    test "string fields filter with case-insensitive contains" do
      render_filter_table(%{"filter" => %{"name" => "Ada"}}, field: :name, filterable: true)

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      # Portable case-insensitive LIKE, not Postgres-only ilike
      assert inspect(where.expr) =~ "LOWER"
      # User input is a literal, lowercased and wrapped in wildcards
      assert Enum.any?(where.params, fn {value, _type} -> value == "%ada%" end)
    end

    test "escapes LIKE wildcards in user input" do
      render_filter_table(%{"filter" => %{"name" => "10%_x"}}, field: :name, filterable: true)

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      assert Enum.any?(where.params, fn {value, _type} -> value == "%10\\%\\_x%" end)
    end

    test "non-string fields cast and filter by equality" do
      render_filter_table(%{"filter" => %{"active" => "true"}}, field: :active, filterable: true)

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      assert inspect(where.expr) =~ "=="
      assert Enum.any?(where.params, fn {value, _type} -> value == true end)
    end

    test "values that fail casting are ignored" do
      render_filter_table(
        %{"filter" => %{"active" => "banana"}},
        field: :active,
        filterable: true
      )

      assert_received {:repo_all, SlabTest.User}
    end

    test "fields not declared filterable are ignored" do
      render_filter_table(%{"filter" => %{"name" => "ada"}}, field: :name)

      assert_received {:repo_all, SlabTest.User}
    end

    test "list values filter with IN" do
      render_filter_table(
        %{"filter" => %{"name" => ["Ada", "Grace"]}},
        field: :name,
        filterable: true
      )

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      assert inspect(where.expr) =~ "in"
      assert Enum.any?(where.params, fn {value, _type} -> value == ["Ada", "Grace"] end)
    end

    test "list values that fail casting are dropped from IN" do
      render_filter_table(
        %{"filter" => %{"active" => ["true", "banana", ""]}},
        field: :active,
        filterable: true
      )

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      assert Enum.any?(where.params, fn {value, _type} -> value == [true] end)
    end

    test "list values with no castable members are ignored" do
      render_filter_table(
        %{"filter" => %{"active" => ["banana"]}},
        field: :active,
        filterable: true
      )

      assert_received {:repo_all, SlabTest.User}
    end

    test "operator maps apply comparison conditions" do
      render_filter_table(
        %{"filter" => %{"inserted_at" => %{"gte" => "2026-01-02T00:00:00Z"}}},
        field: :inserted_at,
        filterable: true
      )

      assert_received {:repo_all, %Ecto.Query{wheres: [where]}}
      assert inspect(where.expr) =~ ">="
    end

    test "unknown operators are ignored" do
      render_filter_table(
        %{"filter" => %{"inserted_at" => %{"drop_table" => "x"}}},
        field: :inserted_at,
        filterable: true
      )

      assert_received {:repo_all, SlabTest.User}
    end

    test "custom filter functions receive the queryable and raw value" do
      test_pid = self()

      custom = fn queryable, value ->
        send(test_pid, {:custom_filter, value})
        queryable
      end

      # No filterable attr — a filter function implies it
      render_filter_table(%{"filter" => %{"name" => "ada"}}, field: :name, filter_query: custom)

      assert_received {:custom_filter, "ada"}
      assert_received {:repo_all, SlabTest.User}
    end
  end

  describe "filter_path/3" do
    test "sets the filter param and resets pagination" do
      assert Slab.filter_path("/users?page=3", :name, "ada") == "/users?filter[name]=ada"
      assert Slab.filter_path("/users?after[id]=abc", :name, "ada") == "/users?filter[name]=ada"
    end

    test "preserves other filters" do
      assert Slab.filter_path("/users?filter[active]=true", :name, "ada") ==
               "/users?filter[active]=true&filter[name]=ada"
    end

    test "clears the filter on nil or empty values" do
      assert Slab.filter_path("/users?filter[name]=ada", :name, nil) == "/users"
      assert Slab.filter_path("/users?filter[name]=ada", :name, "") == "/users"
    end
  end

  describe "table/1 pagination — page mode" do
    test "limits query-mode results and renders next link" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              paginate={:page}
              per_page={2}
              uri={@uri}
              params={@params}
            >
              <:col field={:name} />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users",
          params: %{}
        )

      # Repo returned 3 rows for a limit of per_page + 1; page shows 2
      assert html =~ "Ada"
      assert html =~ "Grace"
      refute html =~ "Katherine"

      # Summary from the count query (FakeRepo.aggregate returns 42)
      assert html =~ "Showing"
      assert html =~ ">1</span>"
      assert html =~ ">2</span>"
      assert html =~ ">42</span>"
      assert html =~ "entries"

      # Numbered links with the current page marked and an ellipsis before
      # the last page (42 entries / 2 per page = 21 pages)
      assert html =~ ~s(aria-current="page")
      assert html =~ ~s(href="/users?page=2")
      assert html =~ ~s(href="/users?page=21")
      assert html =~ "…"

      # No previous link on page 1 (disabled chevron only)
      refute html =~ ~r{<a[^>]*>\s*<span class="sr-only">Previous}

      # Page size dropdown: summary-styled label, plain number options
      assert html =~ ~s(phx-change="per-page")
      assert html =~ ~r{<label[^>]*class="text-sm text-gray-700">Page size</label>}
      assert html =~ ~r{<option value="2" selected>\s*2\s*</option>}
      assert html =~ ~r{<option value="25">\s*25\s*</option>}

      # The query itself was limited and offset, and counted once
      assert_received {:repo_all, %Ecto.Query{} = query}
      assert query.limit
      assert query.offset
      assert_received {:repo_aggregate, SlabTest.User}
    end

    test "renders previous link past page 1, with page 1 dropping the param" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              paginate={:page}
              per_page={2}
              uri={@uri}
              params={@params}
            >
              <:col field={:name} />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users?page=2",
          params: %{"page" => "2"}
        )

      # Previous is a real link; the page 1 link has no page param at all
      assert html =~ ~r{<a[^>]*>\s*<span class="sr-only">Previous}
      assert html =~ ~s(href="/users")
      assert html =~ ~s(href="/users?page=3")

      # Summary window follows the page
      assert html =~ ">3</span>"
      assert html =~ ">4</span>"
    end

    test "paginates list-mode data in memory" do
      data = for n <- 1..5, do: %{id: n, name: "User #{n}"}

      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} paginate={:page} per_page={2} uri={@uri} params={@params}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: data,
          uri: "https://example.com/users?page=2",
          params: %{"page" => "2"}
        )

      refute html =~ "User 2<"
      assert html =~ "User 3"
      assert html =~ "User 4"
      refute html =~ "User 5"
      assert html =~ ~r{<a[^>]*>\s*<span class="sr-only">Previous}
      assert html =~ ~s(href="/users?page=3")

      # List-mode totals come from the list length
      assert html =~ ">5</span>"
    end

    test "last page of list-mode data has no next link" do
      data = for n <- 1..5, do: %{id: n, name: "User #{n}"}

      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data} paginate={:page} per_page={2} uri={@uri} params={@params}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: data,
          uri: "https://example.com/users?page=3",
          params: %{"page" => "3"}
        )

      assert html =~ "User 5"
      # Next is disabled (no link) on the last page; Previous is a link
      refute html =~ ~r{<a[^>]*>\s*<span class="sr-only">Next}
      assert html =~ ~r{<a[^>]*>\s*<span class="sr-only">Previous}
    end

    test "recounts only when filters change, not on page or sort changes" do
      assigns = %{
        id: "test-table",
        data: nil,
        schema: User,
        repo: FakeRepo,
        uri: "https://example.com/users",
        params: %{},
        checkable?: false,
        paginate: :page,
        col: [%{field: :name, sortable: true, filterable: true}]
      }

      {:ok, socket} = Slab.Live.update(assigns, %Phoenix.LiveView.Socket{})
      assert_received {:repo_aggregate, _query}
      assert_received {:repo_all, _query}

      # Page change refetches rows but does not recount
      paged = %{assigns | params: %{"page" => "2"}}
      {:ok, socket} = Slab.Live.update(paged, socket)
      assert_received {:repo_all, _query}
      refute_received {:repo_aggregate, _query}

      # Sort change refetches rows but does not recount
      sorted = %{assigns | params: %{"sort" => "name", "sort_direction" => "asc"}}
      {:ok, socket} = Slab.Live.update(sorted, socket)
      assert_received {:repo_all, _query}
      refute_received {:repo_aggregate, _query}

      # Filter change recounts
      filtered = %{assigns | params: %{"filter" => %{"name" => "ada"}}}
      {:ok, _socket} = Slab.Live.update(filtered, socket)
      assert_received {:repo_all, _query}
      assert_received {:repo_aggregate, _query}
    end

    test "raises when paginating without a uri" do
      assert_raise ArgumentError, ~r/pagination requires uri/, fn ->
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={[]} paginate={:page}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          %{}
        )
      end
    end
  end

  describe "table/1 pagination — cursor mode" do
    test "renders a next link with the last record's id as cursor" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              paginate={:cursor}
              per_page={2}
              uri={@uri}
              params={@params}
            >
              <:col field={:name} />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users",
          params: %{}
        )

      assert html =~ "Ada"
      assert html =~ "Grace"
      refute html =~ "Katherine"

      # Next cursor is the second (last visible) record's id
      assert html =~ "after"
      assert html =~ "594f52e6-936b-4c4f-bfe6-c6d52ce0d05d"
      refute html =~ "First"

      # Ordered by id for a stable total order
      assert_received {:repo_all, %Ecto.Query{} = query}
      assert [_order_by] = query.order_bys
    end

    test "applies a valid cursor as a where condition and offers First" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              paginate={:cursor}
              per_page={2}
              uri={@uri}
              params={@params}
            >
              <:col field={:name} />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users?after[id]=0b937381-b621-4a3f-aa9a-a08e26f04b02",
          params: %{"after" => %{"id" => "0b937381-b621-4a3f-aa9a-a08e26f04b02"}}
        )

      assert_received {:repo_all, %Ecto.Query{wheres: [_where]}}

      # First link drops the cursor
      assert html =~ "First"
      assert html =~ ~s(href="/users")
    end

    test "ignores a cursor that fails type casting" do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table
            id="test-table"
            schema={SlabTest.User}
            repo={SlabTest.FakeRepo}
            paginate={:cursor}
            per_page={2}
            uri={@uri}
            params={@params}
          >
            <:col field={:name} />
          </Slab.table>
          """
        end,
        uri: "https://example.com/users?after[id]=not-a-uuid",
        params: %{"after" => %{"id" => "not-a-uuid"}}
      )

      # Invalid cursor falls back to the first page, never into the query
      assert_received {:repo_all, %Ecto.Query{wheres: []}}
    end

    test "includes the sort value in the cursor when sorting" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              paginate={:cursor}
              per_page={2}
              uri={@uri}
              params={@params}
            >
              <:col field={:inserted_at} sortable />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users?sort=inserted_at&sort_direction=asc",
          params: %{"sort" => "inserted_at", "sort_direction" => "asc"}
        )

      # Cursor carries the last visible record's sort value, ISO 8601 encoded
      # (colons URL-encoded as %3A)
      assert html =~ "after[value]=2026-01-02T12%3A00%3A00Z"

      # Ordered by sort field plus id tiebreaker
      assert_received {:repo_all, %Ecto.Query{order_bys: [order_by]}}
      assert inspect(order_by.expr) =~ ":inserted_at"
      assert inspect(order_by.expr) =~ ":id"
    end

    test "raises with list-mode data" do
      assert_raise ArgumentError, ~r/cursor pagination requires query mode/, fn ->
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={[]} paginate={:cursor} uri="https://example.com/users">
              <:col field={:name} />
            </Slab.table>
            """
          end,
          %{}
        )
      end
    end
  end

  describe "table/1 derived tabs" do
    defp render_tabs_table(attrs) do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table
            id="test-table"
            schema={SlabTest.User}
            repo={SlabTest.FakeRepo}
            uri={@uri}
            params={@params}
            share_tab?={@share_tab?}
          >
            <:col field={:name} filterable={@filterable} />
            <:col field={:active} filterable={@filterable} />
          </Slab.table>
          """
        end,
        Map.merge(
          %{uri: "https://example.com/users", params: %{}, share_tab?: true, filterable: true},
          attrs
        )
      )
    end

    test "renders Filters and Share tabs derived from the table definition" do
      html = render_tabs_table(%{params: %{"filter" => %{"name" => "ada"}}})

      assert html =~ "Filters"
      assert html =~ "Share"

      # Filter inputs generated per filterable column: text for strings,
      # a True/False select for booleans
      assert html =~ ~s(id="test-table-filter-name-form")
      assert html =~ ~s(data-multiple="false")
      assert html =~ "True"

      # The active filter shows in the tab badge and the input value
      assert html =~ ~r{rounded-full">\s*1\s*</div>}
      assert html =~ ~s(value="ada")

      # Share tab holds the current URL
      assert html =~ "Share URL"
      assert html =~ ~s(phx-hook="Slab.CopyToClipboard")

      # Derived tabs open the panel bottom and pull the table card up into
      # it, so the card's rounded corners overlap the panel
      assert html =~ ~s(class="-mb-4")
      assert html =~ "border-b-0 rounded-tr"
      assert html =~ "pb-10"
    end

    test "omits the Filters tab when no columns are filterable" do
      html = render_tabs_table(%{filterable: false})

      refute html =~ "Filters"
      assert html =~ "Share URL"
    end

    test "omits the Share tab by default" do
      html = render_tabs_table(%{share_tab?: false})

      assert html =~ "Filters"
      refute html =~ "Share URL"
    end

    test "col filter_* attrs override the derived input" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              uri={@uri}
              params={@params}
            >
              <:col
                field={:name}
                filterable
                filter_type="multiselect"
                filter_options={[{"Ada", "ada"}, {"Grace", "grace"}]}
              />
              <:col field={:email} filterable filter_placeholder="Search emails..." />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users",
          params: %{}
        )

      # name became a multiselect with the given options
      assert html =~ ~s(data-multiple="true")
      assert html =~ ~s(data-ps-option="ada")
      assert html =~ ~s(data-ps-option="grace")

      # email keeps the derived text input, with the placeholder
      assert html =~ ~s(placeholder="Search emails...")
    end

    test "Ecto.Enum fields derive select options automatically" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table
              id="test-table"
              schema={SlabTest.User}
              repo={SlabTest.FakeRepo}
              uri={@uri}
              params={@params}
            >
              <:col field={:role} filterable />
            </Slab.table>
            """
          end,
          uri: "https://example.com/users",
          params: %{}
        )

      # Enum values become select options without any configuration
      assert html =~ ~s(data-multiple="false")
      assert html =~ ~s(data-ps-option="admin")
      assert html =~ ~s(data-ps-option="member")
      assert html =~ ~s(data-ps-option="guest")
      assert html =~ "Admin"
    end

    test "renders no tab bar without a uri and without filterable columns" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.table id="test-table" data={@data}>
              <:col field={:name} />
            </Slab.table>
            """
          end,
          data: [%{id: 1, name: "Ada"}]
        )

      refute html =~ "test-table-tabs"
    end
  end

  describe "table/1 columns" do
    defp render_columns_table(params, opts \\ []) do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table
            id="test-table"
            data={@data}
            uri={@uri}
            params={@params}
            columns_tab?={@columns_tab?}
          >
            <:col field={:name} />
            <:col field={:email} optional />
            <:col :let={user} label="Actions">Edit {user.name}</:col>
          </Slab.table>
          """
        end,
        data: [%{id: 1, name: "Ada", email: "ada@example.com"}],
        uri: "https://example.com/users",
        params: params,
        columns_tab?: Keyword.get(opts, :columns_tab?, false)
      )
    end

    test "optional columns start hidden" do
      html = render_columns_table(%{})

      assert html =~ "Name"
      assert html =~ "Actions"
      refute html =~ "Email"
      refute html =~ "ada@example.com"
    end

    test "the columns param controls visibility and order" do
      html = render_columns_table(%{"columns" => ["email", "name"]})

      assert html =~ "Email"
      assert html =~ "ada@example.com"
      # Param order wins: email header renders before name
      assert html =~ ~r{Email.*Name}s
      # Not selected, not rendered — including virtual columns
      refute html =~ "Actions"
    end

    test "virtual columns are addressable by label slug" do
      html = render_columns_table(%{"columns" => ["actions", "name"]})

      assert html =~ "Actions"
      assert html =~ "Edit Ada"
      assert html =~ ~r{Actions.*Name}s
      refute html =~ "Email"
    end

    test "unknown names are ignored, and no matches falls back to defaults" do
      html = render_columns_table(%{"columns" => ["nope", "email"]})
      assert html =~ "Email"
      refute html =~ "Name"

      html = render_columns_table(%{"columns" => ["nope"]})
      assert html =~ "Name"
      assert html =~ "Actions"
      refute html =~ "Email"
    end

    test "columns_tab? renders a picker with every column, optional included" do
      html = render_columns_table(%{"columns" => ["name", "email"]}, columns_tab?: true)

      assert html =~ "Table columns"
      assert html =~ ~s(data-ps-option="name")
      assert html =~ ~s(data-ps-option="email")
      assert html =~ ~s(data-ps-option="actions")

      # Current selection appears as removable tags, and the badge counts it
      assert html =~ ~s(data-ps-remove="name")
      assert html =~ ~s(data-ps-remove="email")
      assert html =~ ~r{rounded-full">\s*2\s*</div>}
    end

    test "the Columns tab is absent by default" do
      html = render_columns_table(%{})

      refute html =~ "Table columns"
    end
  end

  describe "table/1 export" do
    defp render_export_table(attrs) do
      render_component(
        fn assigns ->
          ~H"""
          <Slab.table
            id="test-table"
            schema={SlabTest.User}
            repo={SlabTest.FakeRepo}
            paginate={@paginate}
            uri={@uri}
            params={@params}
            export_tab?={@export_tab?}
            export_limit={@export_limit}
          >
            <:col field={:name} />
          </Slab.table>
          """
        end,
        Map.merge(
          %{
            paginate: :page,
            uri: "https://example.com/users",
            params: %{},
            export_tab?: true,
            export_limit: 1000
          },
          attrs
        )
      )
    end

    defp export_socket do
      %Phoenix.LiveView.Socket{private: %{live_temp: %{}}}
    end

    defp export_push_events(socket) do
      socket.private.live_temp[:push_events]
    end

    test "renders the Export tab with both download buttons and the hook" do
      html = render_export_table(%{})

      assert html =~ "Export CSV"
      assert html =~ "Download current page"
      # FakeRepo counts 42 entries, under the limit of 1000
      assert html =~ "Download all data"
      refute html =~ "Download first"

      # The colocated hook's "." prefix expands to the module namespace
      assert html =~ ~s(phx-hook="Slab.Live.Download")
      assert html =~ ~s(data-slab-id="test-table")
      assert html =~ ~s(phx-click="export-current")
      assert html =~ ~s(phx-click="export-limit")
    end

    test "labels the full export by row count when the total exceeds the limit" do
      html = render_export_table(%{export_limit: 10})

      assert html =~ "Download first 10 rows"
      refute html =~ "Download all data"
    end

    test "labels the full export by row count when the total is unknown" do
      html = render_export_table(%{paginate: :cursor})

      assert html =~ "Download first 1000 rows"
      refute html =~ "Download all data"
    end

    test "omits the full export button without pagination" do
      html = render_export_table(%{paginate: nil})

      assert html =~ "Download current page"
      refute html =~ "export-limit"
    end

    test "the Export tab is absent by default" do
      html = render_export_table(%{export_tab?: false})

      refute html =~ "Download current page"
    end

    test "export-current downloads the page as displayed" do
      data = for n <- 1..5, do: %{id: n, name: "User #{n}"}

      assigns = %{
        id: "test-table",
        data: data,
        schema: nil,
        repo: nil,
        uri: "https://example.com/users?page=2",
        params: %{"page" => "2"},
        paginate: :page,
        per_page: 2,
        export_tab?: true,
        col: [%{field: :name}, %{label: "Actions"}]
      }

      {:ok, socket} = Slab.Live.update(assigns, export_socket())
      {:noreply, socket} = Slab.Live.handle_event("export-current", %{}, socket)

      assert [["slab-download-test-table", payload]] = export_push_events(socket)
      assert payload.filename == "test-table-#{Date.utc_today()}.csv"
      assert payload.mime =~ "text/csv"

      # UTF-8 BOM, then the visible page only — virtual columns are skipped
      assert payload.content == "\uFEFFName\r\nUser 3\r\nUser 4\r\n"
    end

    test "export-limit takes the first export_limit rows of list data" do
      data = for n <- 1..5, do: %{id: n, name: "User #{n}"}

      assigns = %{
        id: "test-table",
        data: data,
        schema: nil,
        repo: nil,
        uri: "https://example.com/users?page=2",
        params: %{"page" => "2"},
        paginate: :page,
        per_page: 2,
        export_tab?: true,
        export_limit: 3,
        col: [%{field: :name}]
      }

      {:ok, socket} = Slab.Live.update(assigns, export_socket())
      {:noreply, socket} = Slab.Live.handle_event("export-limit", %{}, socket)

      assert [["slab-download-test-table", payload]] = export_push_events(socket)
      assert payload.content == "\uFEFFName\r\nUser 1\r\nUser 2\r\nUser 3\r\n"
    end

    test "export-limit re-runs the filtered query from the top in query mode" do
      assigns = %{
        id: "test-table",
        data: nil,
        schema: User,
        repo: FakeRepo,
        uri: "https://example.com/users?page=3",
        params: %{"page" => "3", "filter" => %{"name" => "a"}},
        paginate: :page,
        per_page: 2,
        export_tab?: true,
        export_limit: 100,
        col: [%{field: :name, filterable: true}]
      }

      {:ok, socket} = Slab.Live.update(assigns, export_socket())
      assert_received {:repo_all, _page_query}
      {:noreply, socket} = Slab.Live.handle_event("export-limit", %{}, socket)

      # The export query keeps the filter but restarts at record one
      assert_received {:repo_all, %Ecto.Query{} = query}
      assert [_where] = query.wheres
      assert query.limit
      assert inspect(query.offset.params) =~ "{0, :integer}"

      # FakeRepo returns all three users, ignoring the page the viewer was on
      assert [["slab-download-test-table", payload]] = export_push_events(socket)
      assert payload.content == "\uFEFFName\r\nAda\r\nGrace\r\nKatherine\r\n"
    end
  end

  describe "tabs/1" do
    test "renders tab labels with icons, count badges, and toggleable content" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.tabs id="table-tabs" active="Filters">
              <:tab label="Filters" icon="funnel-outline" count={2}>filter content</:tab>
              <:tab label="Share" icon="bookmark-outline" count={0}>share content</:tab>
            </Slab.tabs>
            """
          end,
          %{}
        )

      assert html =~ "Filters"
      assert html =~ "Share"
      assert html =~ "filter content"
      assert html =~ "share content"

      # Count badge renders when positive, hidden when zero
      assert html =~ ~r{rounded-full">\s*2\s*</div>}
      refute html =~ ~r{rounded-full">\s*0\s*</div>}

      # Active tab content is visible, the other hidden
      assert html =~ ~r{id="table-tabs-content-0"[^>]*class="(?!.*hidden)}
      assert html =~ ~r{id="table-tabs-content-1"[^>]*class="[^"]*hidden}

      # Client-side switching via JS commands
      assert html =~ "phx-click"

      # Standalone tabs keep a closed panel (rounded and bordered all around)
      refute html =~ "border-b-0 rounded-tr"
      assert html =~ "rounded-br rounded-bl"
    end

    test "defaults the first tab to active" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.tabs id="table-tabs">
              <:tab label="One">first</:tab>
              <:tab label="Two">second</:tab>
            </Slab.tabs>
            """
          end,
          %{}
        )

      assert html =~ ~r{id="table-tabs-content-0"[^>]*class="(?!.*hidden)}
      assert html =~ ~r{id="table-tabs-content-1"[^>]*class="[^"]*hidden}
    end
  end

  describe "share/1" do
    test "renders the current url with a copy button" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <Slab.share uri={@uri} />
            """
          end,
          uri: "https://example.com/users?filter[name]=ada&sort=name"
        )

      assert html =~ "Share URL"
      assert html =~ ~s(value="https://example.com/users?filter[name]=ada&amp;sort=name")
      assert html =~ "readonly"
      # The colocated hook's "." prefix expands to the module namespace
      assert html =~ ~s(phx-hook="Slab.CopyToClipboard")
      assert html =~ "Copy to clipboard"

      # Input and button share the filter inputs' sizing, so switching tabs
      # doesn't jitter
      assert html =~ ~r{<form class="[^"]*min-h-10[^"]*rounded-lg}
      assert html =~ ~r{<button[^>]*class="min-h-10[^"]*rounded-lg}
    end
  end

  describe "get_filter_count/1" do
    test "counts operator maps per operator" do
      params = %{"filter" => %{"age" => %{"gte" => "21", "lte" => "65"}, "name" => "ada"}}

      assert Slab.get_filter_count(params) == 3
    end

    test "reads from a uri string" do
      assert Slab.get_filter_count("/users?filter[name]=ada&filter[role][]=admin") == 2
    end
  end

  describe "page_path/2" do
    test "sets the page param and clears cursors" do
      assert Slab.page_path("/users?page=2", 3) == "/users?page=3"
      assert Slab.page_path("/users?after[id]=abc", 2) == "/users?page=2"
    end

    test "page 1 drops the param" do
      assert Slab.page_path("/users?page=2", 1) == "/users"
    end
  end

  describe "sort_path/3" do
    test "sorts ascending by a new field" do
      assert Slab.sort_path("/users?q=x", %{}, "name") ==
               "/users?q=x&sort=name&sort_direction=asc"
    end

    test "changing sort resets pagination params" do
      assert Slab.sort_path("/users?page=3", %{}, "name") ==
               "/users?sort=name&sort_direction=asc"

      assert Slab.sort_path("/users?after[id]=abc", %{}, "name") ==
               "/users?sort=name&sort_direction=asc"
    end

    test "flips ascending to descending on the current sort field" do
      params = %{"sort" => "name", "sort_direction" => "asc"}

      assert Slab.sort_path("/users?sort=name&sort_direction=asc", params, "name") ==
               "/users?sort=name&sort_direction=desc"
    end

    test "flips descending back to ascending" do
      params = %{"sort" => "name", "sort_direction" => "desc"}

      assert Slab.sort_path("/users?sort=name&sort_direction=desc", params, "name") ==
               "/users?sort=name&sort_direction=asc"
    end

    test "switching fields resets to ascending" do
      params = %{"sort" => "name", "sort_direction" => "desc"}

      assert Slab.sort_path("/users?sort=name&sort_direction=desc", params, "email") ==
               "/users?sort=email&sort_direction=asc"
    end

    test "strips scheme and host" do
      assert Slab.sort_path("https://example.com/users", %{}, "name") ==
               "/users?sort=name&sort_direction=asc"
    end
  end

  describe "get_checked_ids/1" do
    test "reads from a uri string" do
      assert Slab.get_checked_ids("/users?checked[]=1&checked[]=2") == ["1", "2"]
    end

    test "reads from a params map" do
      assert Slab.get_checked_ids(%{"checked" => [1, 2]}) == ["1", "2"]
    end

    test "returns an empty list when no checked param" do
      assert Slab.get_checked_ids("/users") == []
      assert Slab.get_checked_ids(%{}) == []
    end
  end

  describe "get_checked_values/3" do
    test "filters records by checked ids" do
      records = [%{id: 1, name: "Ada"}, %{id: 2, name: "Grace"}]

      assert Slab.get_checked_values("/users?checked[]=2", records) ==
               [%{id: 2, name: "Grace"}]
    end

    test "supports a custom key" do
      records = [%{uuid: "a", name: "Ada"}, %{uuid: "b", name: "Grace"}]

      assert Slab.get_checked_values("/users?checked[]=a", records, key: :uuid) ==
               [%{uuid: "a", name: "Ada"}]
    end
  end

  describe "checked?/1" do
    test "returns true when any rows are checked" do
      assert Slab.checked?("/users?checked[]=1")
      refute Slab.checked?("/users")
    end
  end

  describe "get_selected_and_missing_ids/3" do
    test "splits selections into current-page records and missing ids" do
      records = [%{id: 1}, %{id: 2}]

      assert Slab.get_selected_and_missing_ids(records, ["2", "3"]) ==
               {[%{id: 2}], ["3"]}
    end
  end
end
