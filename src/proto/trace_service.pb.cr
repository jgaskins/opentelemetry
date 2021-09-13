# # Generated from opentelemetry/proto/collector/trace/v1/trace_service.proto for opentelemetry.proto.collector.trace.v1
require "protobuf"

require "./trace.pb.cr"

module OpenTelemetry
  module Proto
    module Collector
      module Trace
        module V1
          struct ExportTraceServiceRequest
            include ::Protobuf::Message

            contract_of "proto3" do
              repeated :resource_spans, OpenTelemetry::Proto::Trace::V1::ResourceSpans, 1
            end
          end

          struct ExportTraceServiceResponse
            include ::Protobuf::Message
          end
        end
      end
    end
  end
end
