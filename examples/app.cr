require "armature"
require "interro"

require "../src/opentelemetry"
require "../src/integrations/db"

db = DB.open(ENV.fetch("DATABASE_URL", "postgres://localhost/postgres?max_idle_pool_size=30"))
Interro.config do |c|
  c.db = db
end

OpenTelemetry.configure do |c|
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

products = ProductQuery.new
if products.size == 0
  50.times do |i|
    products.create(
      name: "Product #{i + 1}",
      description: "This is product ##{i + 1}",
      price: Money.new(rand(1_00...1_000_00)),
    )
  end
end

class App
  include HTTP::Handler
  include Armature::Route

  def call(context)
    route context do |r, response|
      r.on "catalog" { Catalog.new.call context }
    end
  end

  struct Catalog
    include Armature::Route

    def call(context)
      route context do |r, response|
        r.root do
          r.get do
            products = 0
            OpenTelemetry.trace "ProductQuery" do |span|
              span.kind = :client
              query = ProductQuery.new
              span["query.sql"] = query.to_sql

              query.each do |product|
                OpenTelemetry.trace "render" do |span|
                  span["template"] = "examples/views/products/list_item.ecr"
                  ECR.embed "examples/views/products/list_item.ecr", response
                end
                products += 1
              end
            end

            # OpenTelemetry.context product_count: products
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
end

http = HTTP::Server.new([
  HTTP::LogHandler.new,
  OpenTelemetry::Middleware.new("http.server.request"),
  App.new,
])
port = ENV.fetch("PORT", "3000").to_i
puts "Listening on #{port}..."
http.listen port
