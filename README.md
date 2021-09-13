# OpenTelemetry

[OpenTelemetry](https://opentelemetry.io) is an observability framework for cloud-native software.

This Crystal shard allows you to add it to your applications to export application telemetry to OpenTelemetry-compatible services, such as:

- [Honeycomb](https://honeycomb.io)
- [Datadog](https://www.datadoghq.com)
- [Prometheus](https://prometheus.io)
- [New Relic](https://newrelic.com/)
- [Lightstep](https://lightstep.com)

You can see more at the OpenTelemetry website.

## Installation

1. Add the dependency to your `shard.yml`:

   ```
   dependencies:
     opentelemetry:
       github: jgaskins/opentelemetry
   ```

2. Run `shards install`

## Usage

To use this shard, you'll need to have a service setup to receive OpenTelemetry data. In this example, we'll use Honeycomb:

```crystal
require "opentelemetry"

OpenTelemetry.configure do |c|
  c.exporter = OpenTelemetry::BatchExporter.new(
    OpenTelemetry::HTTPExporter.new(
      endpoint: URI.parse("https://api.honeycomb.io"),
      headers: HTTP::Headers{
        # Get your Honeycomb API key from https://ui.honeycomb.io/account
        "x-honeycomb-team"    => ENV["HONEYCOMB_API_KEY"],
        # Name this whatever you like. Honeycomb will create the dataset when it
        # begins reporting data.
        "x-honeycomb-dataset" => ENV["HONEYCOMB_DATASET"],
      },
    )
  )
end
```

### Instrumenting

Use the `OpenTelemetry.trace` method to create a new trace for the current fiber or to add a span inside the current trace.

```crystal
OpenTelemetry.trace "outer-span" do |span|
  # do some work

  OpenTelemetry.trace "inner-span" do |span|
    # do some work
  end

  # do some work
end
```

### Integrations

You enable integrations simply by requiring them. They will be instrumented automatically.

```crystal
# Load the integration for the crystal-lang/crystal-db shard
require "opentelemetry/integrations/db"
```

You can see all of the integrations available in [the integrations directory](https://github.com/jgaskins/opentelemetry/tree/main/src/integrations).

## Contributing

1. Fork it (<https://github.com/jgaskins/opentelemetry/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
