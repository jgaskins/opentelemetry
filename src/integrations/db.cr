require "db"

class DB::Statement
  def_around_query_or_exec do |args|
    operation = command[0...command.index(' ')]

    OpenTelemetry.trace operation do |span|
      uri = connection.context.uri
      span["query.sql"] = command
      span["query.args"] = args.map(&.inspect).join(", ")
      span["host"] = uri.host
      span["db"] = uri.path[1..]
      db_uri = connection
        .context
        .uri
        .dup
        .tap { |uri| uri.password = "FILTERED" }

      # Span attribute conventions from:
      #   https://github.com/open-telemetry/opentelemetry-specification/blob/82b5317f55931bb3a6208c217dc5c730001d0670/specification/trace/semantic_conventions/database.md#mysql
      span["db.system"] = db_uri.scheme
      span["db.connection_string"] = db_uri.to_s
      span["db.user"] = db_uri.user
      span["net.peer.name"] = db_uri.host
      span["net.peer.port"] = db_uri.port
      span["net.transport"] = "IP.TCP"
      span["db.name"] = db_uri.path[1..]
      span["db.statement"] = command
      span["db.operation"] = operation
      span.kind = :client

      yield
    end
  end
end

module DB::BeginTransaction
  def transaction
    OpenTelemetry.trace "db.transaction" do |span|
      previous_def do |txn|
        yield txn
      end
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
