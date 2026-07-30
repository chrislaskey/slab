# Seeds ~150 deterministic users — with organizations and products — so the
# demo tables have data to sort, filter, paginate, preload, and export.
# Run with: mix run priv/repo/seeds.exs

first_names = ~w(Ada Grace Katherine Alan Edsger Barbara Donald Margaret John Radia
  Annie Dennis Frances Ken Adele Linus Hedy Tim Joan Bjarne)

last_names = ~w(Lovelace Hopper Johnson Turing Dijkstra Liskov Knuth Hamilton
  Backus Perlman Easley Ritchie Allen Thompson Goldstine Torvalds Lamarr
  Berners-Lee Clarke Stroustrup)

roles = [:admin, :member, :guest]

now = DateTime.utc_now() |> DateTime.truncate(:second)

organizations =
  for name <- ["Acme Analytics", "Bletchley Labs", "Fairchild Systems", "Bell Labs", "Xerox PARC"] do
    Demo.Repo.insert!(%Demo.Accounts.Organization{name: name})
  end

users =
  for {first, i} <- Enum.with_index(first_names),
      {last, j} <- Enum.with_index(last_names),
      # 150 of the 400 combinations
      rem(i * 20 + j, 8) < 3 do
    n = i * 20 + j

    %{
      name: "#{first} #{last}",
      email: "#{String.downcase(first)}.#{String.downcase(last)}@example.com",
      role: Enum.at(roles, rem(n, 3)),
      active: rem(n, 4) != 0,
      organization_id: Enum.at(organizations, rem(n, 5)).id,
      # Spread creation times over the past ~100 days
      inserted_at: DateTime.add(now, -n * 16 * 3600, :second),
      updated_at: now
    }
  end

Demo.Repo.insert_all(Demo.Accounts.User, users)

# Zero to three products per user, deterministic by user id
product_names = ["Compiler Pro", "Debugger", "Profiler", "Linter", "Formatter"]

products =
  for user <- Demo.Repo.all(Demo.Accounts.User),
      offset <- 0..(rem(user.id, 4) - 1)//1 do
    %{
      name: Enum.at(product_names, rem(user.id + offset, 5)),
      user_id: user.id,
      inserted_at: now,
      updated_at: now
    }
  end

Demo.Repo.insert_all(Demo.Accounts.Product, products)

IO.puts("Seeded #{length(organizations)} organizations, #{length(users)} users, #{length(products)} products")
