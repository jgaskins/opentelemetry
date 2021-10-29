require "db"

class DB::Statement
  def_around_query_or_exec do |args|
    query = command.strip.gsub(/\s+/, ' ')
    operation = query.strip[0...command.index(' ')]

    OpenTelemetry.trace query do |span|
      db_uri = connection
        .context
        .uri
        .dup
        .tap { |uri| uri.password = "FILTERED" }
      statement_args = args.map do |arg|
        if arg.class.name =~ /password/i
          arg = "[FILTERED]"
        end

        arg.inspect
      end

      # Span attribute conventions from:
      #   https://github.com/open-telemetry/opentelemetry-specification/blob/82b5317f55931bb3a6208c217dc5c730001d0670/specification/trace/semantic_conventions/database.md#mysql
      db_system = case scheme = db_uri.scheme
                  when "postgres"
                    "postgresql"
                  else
                    scheme
                  end
      span["db.system"] = db_system
      span["db.connection_string"] = db_uri.to_s
      span["db.user"] = db_uri.user
      span["net.peer.name"] = db_uri.host || "localhost"
      span["net.peer.port"] = db_uri.port || 5432 # FIXME: Make this work for non-Postgres DBs
      span["net.transport"] = "ip_tcp"
      span["db.name"] = db_uri.path[1..]
      span["db.statement"] = command
      span["db.statement_args"] = statement_args.join(", ")
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
    query = statement.command.strip.gsub(/\s+/, ' ')
    operation = query.strip[0...statement.command.index(' ')]

    OpenTelemetry.trace "db.result_set.each" do |span|
      db_uri = uri.dup.tap { |uri| uri.password = "FILTERED" }
      # TODO: Can we get these?
      # statement_args = statement.args.map do |arg|
      #   if arg.class.name =~ /password/i
      #     arg = "[FILTERED]"
      #   end

      #   arg.inspect
      # end

      # Span attribute conventions from:
      #   https://github.com/open-telemetry/opentelemetry-specification/blob/82b5317f55931bb3a6208c217dc5c730001d0670/specification/trace/semantic_conventions/database.md#mysql
      db_system = case scheme = db_uri.scheme
                  when "postgres"
                    "postgresql"
                  else
                    scheme
                  end
      span["db.system"] = db_system
      span["db.connection_string"] = db_uri.to_s
      span["db.user"] = db_uri.user
      span["net.peer.name"] = db_uri.host || "localhost"
      span["net.peer.port"] = db_uri.port || 5432 # FIXME: Make this work for non-Postgres DBs
      span["net.transport"] = "ip_tcp"
      span["db.name"] = db_uri.path[1..]
      span["db.statement"] = statement.command
      # span["db.statement_args"] = statement_args.join(", ")
      span["db.operation"] = operation
      span.kind = :client
      result_count = 0

      begin
        previous_def do
          result_count += 1
          yield
        end
      ensure
        span["db.row_count"] = result_count
        span["db.column_count"] = column_count
      end
    end
  end
end
