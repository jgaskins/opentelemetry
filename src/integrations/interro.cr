require "interro"

module Interro
  def self.transaction
    OpenTelemetry.trace "interro.transaction" do |span|
      previous_def do |txn|
        yield txn
      end
    end
  end
end

struct Interro::QueryBuilder(T)
  def each : Nil
    OpenTelemetry.trace self.class.name do |span|
      db_uri = Interro::CONFIG
        .read_db
        .uri
        .dup
        .tap { |uri| uri.password = "FILTERED" }
      sql = to_sql.strip
      statement_args = args.map do |arg|
        if arg.class.name =~ /password/i
          "[FILTERED]"
        end

        arg.inspect
      end

      # Span attribute conventions from:
      #   https://github.com/open-telemetry/opentelemetry-specification/blob/82b5317f55931bb3a6208c217dc5c730001d0670/specification/trace/semantic_conventions/database.md#mysql
      span["db.system"] = "postgresql"
      span["db.connection_string"] = db_uri.to_s
      span["db.user"] = db_uri.user
      span["net.peer.name"] = db_uri.host || "localhost"
      span["net.peer.port"] = db_uri.port || 5432
      span["net.transport"] = "ip_tcp"
      span["db.name"] = db_uri.path[1..]
      span["db.statement"] = sql
      span["db.statement_args"] = statement_args.join(", ")
      span["db.operation"] = sql[0...sql.index(' ')]
      span["db.sql.table"] = sql_table_name
      span.kind = :client

      results = 0
      previous_def do |result|
        yield result
        results += 1
      end
      span["db.result_count"] = results
    end
  end
end
