# # Generated from opentelemetry/proto/common/v1/common.proto for opentelemetry.proto.common.v1
require "protobuf"

module OpenTelemetry
  module Proto
    module Common
      module V1
        struct AnyValue
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :string_value, :string, 1
            optional :bool_value, :bool, 2
            optional :int_value, :int64, 3
            optional :double_value, :double, 4
            optional :array_value, ArrayValue, 5
            optional :kvlist_value, KeyValueList, 6
            optional :bytes_value, :bytes, 7
          end
        end

        struct ArrayValue
          include ::Protobuf::Message

          contract_of "proto3" do
            repeated :values, AnyValue, 1
          end
        end

        struct KeyValueList
          include ::Protobuf::Message

          contract_of "proto3" do
            repeated :values, KeyValue, 1
          end
        end

        struct KeyValue
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :key, :string, 1
            optional :value, AnyValue, 2
          end
        end

        struct StringKeyValue
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :key, :string, 1
            optional :value, :string, 2
          end
        end

        struct InstrumentationLibrary
          include ::Protobuf::Message

          contract_of "proto3" do
            optional :name, :string, 1
            optional :version, :string, 2
          end
        end
      end
    end
  end
end
