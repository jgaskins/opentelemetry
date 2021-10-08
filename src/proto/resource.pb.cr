# # Generated from opentelemetry/proto/resource/v1/resource.proto for opentelemetry.proto.resource.v1
require "protobuf"

require "./common.pb.cr"

module OpenTelemetry
  module Proto
    module Resource
      module V1
        struct Resource
          include ::Protobuf::Message

          contract_of "proto3" do
            repeated :attributes, OpenTelemetry::Proto::Common::V1::KeyValue, 1
            optional :dropped_attributes_count, :uint32, 2
          end
        end
      end
    end
  end
end
