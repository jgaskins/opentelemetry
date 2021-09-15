require "redis"

class Redis::Connection
  def run(command, retries = 5)
    span_name = command[0..1].join(' ')

    OpenTelemetry.trace span_name do |span|
      span["db.system"] = "redis"
      span["net.peer.name"] = @uri.host
      case socket = @socket
      when TCPSocket, OpenSSL::SSL::Socket::Client
        span["net.transport"] = "IP.TCP"
      when UNIXSocket
        span["net.transport"] = "Unix"
      end
      span["db.statement"] = command.join(' ')
      span["db.redis.database_index"] = @uri.path[1..].presence

      result = previous_def

      case result
      when Array
      end

      result
    end
  end
end
