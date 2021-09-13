# # Generated from opentelemetry/proto/trace/v1/trace.proto for opentelemetry.proto.trace.v1
require "protobuf"

require "./common.pb.cr"
require "./resource.pb.cr"

module OpenTelemetry
  module Proto
    module Trace
      module V1
        class ResourceSpans
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :resource, OpenTelemetry::Proto::Resource::V1::Resource, 1
            repeated :instrumentation_library_spans, InstrumentationLibrarySpans, 2
            optional :schema_url, :string, 3
          end
        end

        class InstrumentationLibrarySpans
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :instrumentation_library, OpenTelemetry::Proto::Common::V1::InstrumentationLibrary, 1
            repeated :spans, Span, 2
            optional :schema_url, :string, 3
          end
        end

        class Span
          include ::Protobuf::Message
          enum SpanKind
            UNSPECIFIED = 0
            INTERNAL    = 1
            SERVER      = 2
            CLIENT      = 3
            PRODUCER    = 4
            CONSUMER    = 5
          end

          class Event
            include ::Protobuf::Message

            contract_of "proto3" do
              optional :time_unix_nano, :fixed64, 1
              optional :name, :string, 2
              repeated :attributes, OpenTelemetry::Proto::Common::V1::KeyValue, 3
              optional :dropped_attributes_count, :uint32, 4
            end
          end

          class Link
            include ::Protobuf::Message

            contract_of "proto3" do
              optional :trace_id, :bytes, 1
              optional :span_id, :bytes, 2
              optional :trace_state, :string, 3
              repeated :attributes, OpenTelemetry::Proto::Common::V1::KeyValue, 4
              optional :dropped_attributes_count, :uint32, 5
            end
          end

          contract_of "proto3" do
            optional :trace_id, :bytes, 1
            optional :span_id, :bytes, 2
            optional :trace_state, :string, 3
            optional :parent_span_id, :bytes, 4
            optional :name, :string, 5
            optional :kind, Span::SpanKind, 6
            optional :start_time_unix_nano, :fixed64, 7
            optional :end_time_unix_nano, :fixed64, 8
            repeated :attributes, OpenTelemetry::Proto::Common::V1::KeyValue, 9
            optional :dropped_attributes_count, :uint32, 10
            repeated :events, Span::Event, 11
            optional :dropped_events_count, :uint32, 12
            repeated :links, Span::Link, 13
            optional :dropped_links_count, :uint32, 14
            optional :status, Status, 15
          end
        end

        class Status
          include ::Protobuf::Message
          enum DeprecatedStatusCode
            OK                  =  0
            CANCELLED           =  1
            UNKNOWN_ERROR       =  2
            INVALID_ARGUMENT    =  3
            DEADLINE_EXCEEDED   =  4
            NOT_FOUND           =  5
            ALREADY_EXISTS      =  6
            PERMISSION_DENIED   =  7
            RESOURCE_EXHAUSTED  =  8
            FAILED_PRECONDITION =  9
            ABORTED             = 10
            OUT_OF_RANGE        = 11
            UNIMPLEMENTED       = 12
            INTERNAL_ERROR      = 13
            UNAVAILABLE         = 14
            DATA_LOSS           = 15
            UNAUTHENTICATED     = 16
          end
          enum StatusCode
            UNSET = 0
            OK    = 1
            ERROR = 2
          end

          contract_of "proto3" do
            optional :deprecated_code, Status::DeprecatedStatusCode, 1
            optional :message, :string, 2
            optional :code, Status::StatusCode, 3
          end
        end
      end
    end
  end
end
