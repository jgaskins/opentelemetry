require "spec"
require "../src/exporter"

TEST_EXPORTER = TestExporter.new

OpenTelemetry.configure do |c|
  # Make it so that we can test the traces by "exporting" to an in-memory
  # representation that we can query.
  c.exporter = TEST_EXPORTER
end

class TestExporter
  include OpenTelemetry::Exporter

  getter traces = Array(Trace).new

  def trace(traces : Array(Trace))
    @traces += traces
  end

  def clear_traces!
    @traces.clear
  end
end
