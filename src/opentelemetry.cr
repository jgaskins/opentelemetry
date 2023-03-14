require "db/pool"
require "http"

require "./ext/fiber"

require "./exporter"
require "./proto/trace.pb"
require "./proto/trace_service.pb"

# TODO: Write documentation for `OpenTelemetry`
module OpenTelemetry
  VERSION = "0.3.4"

  # The primary interface for OpenTelemetry tracing, called whenever you want to
  # either create a new trace or add nested spans to an existing trace.
  #
  # ```
  # def query(sql : String, args : Array)
  #   OpenTelemetry.trace "db.query" do |span|
  #     span["query.sql"] = sql
  #     span["query.args"] = args.to_s
  #     result = run_query(sql, args)
  #     span["query.result_count"] = result.size
  #
  #     result
  #   end
  # end
  # ```
  def self.trace(name : String)
    trace = current_trace
    trace.resource = CONFIG.resource
    is_new_trace = current_trace_id.nil?
    trace_id = self.current_trace_id ||= Random::Secure.random_bytes(16)
    previous_current_span = current_span
    span = API::Span.new(
      name: name,
      trace_id: trace_id,
      parent_id: previous_current_span.try(&.id),
      kind: :internal
    )
    self.current_span = span
    span["service.name"] = CONFIG.service_name

    span.started!
    trace.spans << span

    begin
      yield span
    rescue ex
      span.status = Proto::Trace::V1::Status.new(
        code: :error,
        message: "#{ex.class.name}: #{ex.message}",
      )
      raise ex
    ensure
      span.ended!
      Fiber.current.current_otel_span = previous_current_span

      if previous_current_span.nil?
        self.current_trace_id = nil if is_new_trace
        CONFIG.exporter.trace(trace.to_protobuf)
        reset_current_trace!
      end
    end
  end

  # :nodoc:
  def self.current_trace_id
    Fiber.current.current_otel_trace_id
  end

  # :nodoc:
  def self.current_trace_id=(value : Bytes?)
    Fiber.current.current_otel_trace_id = value
  end

  # :nodoc:
  def self.current_trace
    Fiber.current.current_otel_trace!
  end

  # :nodoc:
  def self.reset_current_trace!
    Fiber.current.current_otel_trace = nil
  end

  # :nodoc:
  def self.current_span
    Fiber.current.current_otel_span
  end

  # :nodoc:
  def self.current_span=(span : API::Span)
    Fiber.current.current_otel_span = span
  end

  # Global OpenTelemetry configuration, intended to be called when your
  # application starts. Supports loading configs from `OTEL_SERVICE_NAME` and
  # `OTEL_RESOURCE_ATTRIBUTES` environment variables but it won't override what
  # was previously configured in the block. See `OpenTelemetry::Configuration`
  # for more details.
  #
  # ```
  # OpenTelemetry.configure do |c|
  #   c.service_name = "crystal-service"
  #   c.exporter = OpenTelemetry::HTTPExporter.new(
  #     # Send data to Honeycomb
  #     endpoint: URI.parse("https://api.honeycomb.io")
  #     headers: HTTP::Headers {
  #       "x-honeycomb-team"    => ENV["HONEYCOMB_API_KEY"],
  #       "x-honeycomb-dataset" => ENV["HONEYCOMB_DATASET"],
  #     }
  #   )
  # end
  # ```
  def self.configure
    CONFIG.service_name = ENV["OTEL_SERVICE_NAME"]?

    yield CONFIG

    # No need to configure the resource if already assigned within yield block
    return unless CONFIG.resource.nil?

    resource_attributes = [] of Proto::Common::V1::KeyValue
    if CONFIG.service_name.presence
      resource_attributes << Proto::Common::V1::KeyValue.new(
        key: "service.name",
        value: Proto::Common::V1::AnyValue.new(CONFIG.service_name)
      )
    end

    if env_resource_attributes = ENV["OTEL_RESOURCE_ATTRIBUTES"]?
      env_resource_attributes.split(',').each do |attribute|
        key, value = attribute.split('=')

        # Skip if service name was already defined (previous takes precedence)
        next if key == "service.name" && CONFIG.service_name.presence

        # Ensure service name is loaded to CONFIG if assigned here
        CONFIG.service_name = value if key == "service.name"

        resource_attributes << Proto::Common::V1::KeyValue.new(
          key: key,
          value: Proto::Common::V1::AnyValue.new(value)
        )
      end
    end

    # Create shared resource if service name was assigned
    if CONFIG.service_name.presence
      CONFIG.resource = Proto::Resource::V1::Resource.new(
        attributes: resource_attributes
      )
    end
  end

  # Configuration for OpenTelemetry, see `OpenTelemetry.configure` for usage.
  class Configuration
    # Set the `OpenTelemetry::Exporter` instance.
    property exporter : Exporter = NullExporter.new
    property service_name : String? = ""
    property resource : Proto::Resource::V1::Resource? = nil
  end

  # :nodoc:
  CONFIG = Configuration.new

  # An `HTTP::Handler` compatible with any `HTTP::Server`-based framework,
  # including [Lucky](https://luckyframework.org) and [Amber](https://amberframework.org).
  #
  # For plain `HTTP::Server`:
  #
  # ```
  # http = HTTP::Server.new([
  #   HTTP::LogHandler.new,
  #   OpenTelemetry::Middleware.new("top-level-span-name"),
  #   YourApp.new,
  # ])
  # ```
  class Middleware
    include HTTP::Handler

    def initialize(@name : String)
    end

    def call(context : HTTP::Server::Context)
      OpenTelemetry.trace @name do |span|
        span.kind = :server
        span["http.server_name"] = context.request.headers["host"]?
        span["http.client_ip"] = context.request.headers["x-forward-for"]? || context.request.remote_address.as(Socket::IPAddress).address
        span["http.user_agent"] = context.request.headers["user-agent"]?
        span["http.path"] = context.request.path
        span["http.method"] = context.request.method
        span["http.target"] = context.request.resource
        span["http.flavor"] = context.request.version
        span["http.host"] = context.request.headers["host"]?
        context.request.query_params.each do |key, value|
          span["request.query_params.#{key}"] = value
        end

        begin
          call_next context
        ensure
          span["http.status_code"] = context.response.status_code.to_i64
          if context.response.status_code < 400
            span.status = Proto::Trace::V1::Status.new(code: :ok)
          end
          # pp current_trace: OpenTelemetry.current_trace
        end
      end
    end
  end
end
