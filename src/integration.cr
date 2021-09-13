module OpenTelemetry
  def self.integration(name : Enumerable(String)) : Integration?
    Integrations::MAP[name]?
  end

  def self.register(name : Enumerable(String), integration : Integration)
    Integrations::MAP[name] = integration
  end

  module Integrations
    MAP = {} of Enumerable(String) => Integration
  end

  module Integration
    abstract def trace(name : String, tags = {} of String => String, & : OpenTelemetry::Proto::Trace::V1::Span ->)
  end
end
