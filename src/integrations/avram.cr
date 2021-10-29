require "avram"

module Avram::Queryable(T)
  def results
    OpenTelemetry.trace self.class.name do |span|
      # Largely copied from src/integrations/db.cr and tweaked for Avram
      assign_otel_attributes span, operation: "SELECT"

      result = previous_def
      span["db.row_count"] = result.size
      result
    end
  end

  def delete
    OpenTelemetry.trace "#{self.class.name}#delete" do |span|
      assign_otel_attributes span, operation: "DELETE"

      result = previous_def
      span["db.row_count"] = result
      result
    end
  end

  private def assign_otel_attributes(span, operation)
    span["net.transport"] = "ip_tcp"
    span["db.table"] = query.table.to_s
    span["db.system"] = "postgresql"
    sql = to_sql.join(", ")
    span["db.statement"] = sql
    span["db.operation"] = operation
    span.kind = :client

    # TODO: Is there a way to get these attributes in Avram?
    # span["db.connection_string"] = db_uri.to_s
    # span["db.user"] = db_uri.user
    # span["net.peer.name"] = db_uri.host
    # span["net.peer.port"] = db_uri.port
    # span["db.name"] = db_uri.path[1..]
  end
end

class Avram::SaveOperation(T)
  def save
    OpenTelemetry.trace "#{self.class.name}#save" do |span|
      previous_def
    end
  end
end
