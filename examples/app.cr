require "armature"
require "armature/redis_session"
require "interro"

require "../src/opentelemetry"
require "../src/integrations/db"
require "../src/integrations/armature"
require "../src/integrations/interro"
require "../src/integrations/redis"

db = DB.open(ENV.fetch("DATABASE_URL", "postgres://localhost/postgres?max_idle_pool_size=30"))
Interro.config do |c|
  c.db = db
end

OpenTelemetry.configure do |c|
  c.service_name = "Example App"
  c.exporter = OpenTelemetry::BatchExporter.new(
    OpenTelemetry::HTTPExporter.new(
      endpoint: URI.parse("https://api.honeycomb.io"),
      headers: HTTP::Headers{
        "x-honeycomb-team"    => ENV["HONEYCOMB_API_KEY"],
        "x-honeycomb-dataset" => "http.server",
      },
    )
  )
end

db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS example_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    price INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )
SQL

db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS example_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )
SQL

products = ProductQuery.new
if products.size == 0
  puts "Seeding products..."
  50.times do |i|
    products.create(
      name: "Product #{i + 1}",
      description: "This is product ##{i + 1}",
      price: Money.new(rand(1_00...1_000_00)),
    )
  end
end

if UserQuery.new.count == 0
  puts "Seeding users..."
  UserQuery.new.create(
    email: "me@example.com",
    name: "Foo Bar",
  )
end

class App
  include HTTP::Handler
  include Armature::Route

  def call(context)
    route context do |r, response, session|
      # Load session data from Redis by referencing a session key
      if current_user_id = session["user_id"]?.try(&.as_s?)
        current_user = UserQuery.new.find_by(id: UUID.new(current_user_id))
      end

      ECR.embed "examples/views/app_header.ecr", response

      r.on "login" do
        r.post do
          if current_user = UserQuery.new.find_by(email: "me@example.com")
            session["user_id"] = current_user.id.to_s
          end

          response.redirect r.headers["referer"]? || "/catalog"
        end
      end

      r.on "catalog" { Catalog.new.call context }

      r.miss do
        response.status = :not_found
        response << "<h1>Not found</h1>"
      end

      if current_user
        OpenTelemetry.current_trace.instrumentation_library_spans.not_nil!.flat_map(&.spans.not_nil!).each do |span|
          span["user.id"] = current_user.id.to_s
          span["user.email"] = current_user.email
          span["user.name"] = current_user.name
        end
      end
    end
  end

  struct Catalog
    include Armature::Route

    def call(context)
      route context do |r, response, session|
        r.root do
          r.post {}

          r.get do
            products = 0
            Interro.transaction do |txn|
              ProductQuery[txn].each do |product|
                ECR.embed "examples/views/products/list_item.ecr", response
                products += 1
              end
            end
          end
        end

        r.on :id do |id|
          r.get do
            product = ProductQuery.new.find_by(id: id)

            if product
              ECR.embed "examples/views/products/list_item.ecr", response
            else
              response.status = :not_found
              response << "Not found"
            end
          end
        end
      end
    end
  end
end

struct Product
  include DB::Serializable

  getter id : UUID
  getter name : String
  getter description : String
  @[DB::Field(converter: Money)]
  getter price : Money
  getter created_at : Time
end

struct User
  include DB::Serializable

  getter id : UUID
  getter name : String
  getter email : String
  getter created_at : Time
  getter updated_at : Time
end

record Money, total_cents : Int32 do
  def self.from_rs(rs : DB::ResultSet)
    new rs.read(Int32)
  end

  def dollars
    @total_cents // 100
  end

  def cents
    @total_cents % 100
  end

  def to_s(io)
    io << '$'
    (total_cents / 100).round(2).format io, decimal_places: 2
  end
end

struct PQ::Param
  def self.encode(money : Money)
    encode money.total_cents
  end
end

struct ProductQuery < Interro::QueryBuilder(Product)
  table "example_products"

  def create(name : String, description : String, price : Money)
    insert name: name, description: description, price: price
  end

  def find_by(*, id : String)
    where(id: id).first?
  end
end

struct UserQuery < Interro::QueryBuilder(User)
  table "example_users"

  def find_by(*, id : UUID)
    where(id: id).first?
  end

  def find_by(*, email : String)
    where(email: email).first?
  end

  def create(email : String, name : String)
    insert email: email,  name: name
  end
end

http = HTTP::Server.new([
  HTTP::LogHandler.new,
  OpenTelemetry::Middleware.new("http.server.request"),
  Armature::Session::RedisStore.new(
    redis: Redis::Client.new,
    key: "otel_example_session",
  ),
  App.new,
])
port = ENV.fetch("PORT", "3000").to_i
puts "Listening on #{port}..."
http.listen port
