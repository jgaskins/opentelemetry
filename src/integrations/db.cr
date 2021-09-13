require "db"

class DB::Statement
  def_around_query_or_exec do |args|
    OpenTelemetry.trace "db.query" do |span|
      uri = connection.context.uri
      span["query.sql"] = command
      span["query.args"] = args.map(&.inspect).join(", ")
      span["host"] = uri.host
      span["db"] = uri.path[1..]
      span.kind = :client

      yield
    end
  end
end

class DB::ResultSet
  def each
    uri = statement.connection.context.uri
    host = uri.host
    db = uri.path[1..-1]

    OpenTelemetry.trace "db.result_set.each" do |span|
      span["query.sql"] = statement.command
      span["host"] = host
      span["db"] = db
      span.kind = :client
      result_count = 0

      begin
        previous_def do
          result_count += 1
          yield
        end
      ensure
        span["row_count"] = result_count
        span["column_count"] = column_count
      end
    end
  end
end
