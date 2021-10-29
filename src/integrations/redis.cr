require "redis"

class Redis::Connection
  def run(command, retries = 5)
    span_name = command[0..1].join(' ')

    OpenTelemetry.trace span_name do |span|
      span["db.system"] = "redis"
      span["net.peer.name"] = @uri.host
      case socket = @socket
      when TCPSocket, OpenSSL::SSL::Socket::Client
        span["net.transport"] = "ip_tcp"
      when UNIXSocket
        span["net.transport"] = "Unix"
      end
      span["db.statement"] = command.map(&.inspect_unquoted).join(' ')
      span["db.redis.database_index"] = (@uri.path.presence || "/")[1..].presence
      span.kind = :client

      result = previous_def

      result
    end
  end
end
