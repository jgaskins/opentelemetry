require "./spec_helper"

require "../src/opentelemetry"

describe OpenTelemetry do
  before_each { TEST_EXPORTER.clear_traces! }

  it "generates a trace with spans" do
    OpenTelemetry.trace "span-name" { |span| span["foo"] = "bar" }

    span = spans.first

    span.name.should eq "span-name"
    span["foo"].should eq "bar"
  end

  it "generates a trace with multiple spans" do
    OpenTelemetry.trace "outer" do |span|
      span["which-one"] = "first"

      OpenTelemetry.trace "inner" do |span|
        span["which-one"] = "second"
      end
    end

    # For some reason the spans are added in a different order, so we're finding
    # by name here. This can be simplified if we want to guarantee order, but
    # that may not be necessary.
    first = spans.find { |s| s.name == "outer" }.not_nil!
    second = spans.find { |s| s.name == "inner" }.not_nil!

    first["which-one"].should eq "first"
    first.name.should eq "outer"
    second["which-one"].should eq "second"
    second.name.should eq "inner"
    second.parent_span_id.should eq first.span_id
    second.trace_id.should eq first.trace_id
  end

  it "can generate multiple traces" do
    OpenTelemetry.trace "first" { }
    OpenTelemetry.trace "second" { }

    traces = TEST_EXPORTER.traces

    traces.size.should eq 2
    span_names = spans.map(&.name)

    span_names.should eq %w[first second]
  end

  it "can memoize span attributes" do
    OpenTelemetry.trace "" do |span|
      (span["key"] ||= "value").should eq "value"
      (span["key"] ||= "another value").should eq "value"
      span["key"]?.should eq "value"
    end

    spans.first["key"].should eq "value"
  end

  it "changes an attribute value when directly assigning" do
    OpenTelemetry.trace "" do |span|
      span["key"] = "first value"
      span["key"] = "second value"
    end

    spans.first["key"].should eq "second value"
  end

  # The service_name config option is set in spec_helper.cr
  it "sets the service.name attribute with the service_name configuration option" do
    OpenTelemetry.trace "lol" { }

    spans.first["service.name"].should eq "Test App"
  end
end

private def spans
  # TODO: Make this traversal suck less
  TEST_EXPORTER.traces
    .flat_map(&.instrumentation_library_spans.not_nil!)
    .flat_map(&.spans.not_nil!)
end
