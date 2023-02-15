require "./ext/fiber"

require "./proto/trace.pb"
require "./proto/trace_service.pb"

module OpenTelemetry
  module API
    class Trace
      getter id : Bytes = Random::Secure.random_bytes(16)
      getter spans = [] of Span

      def to_protobuf
        Proto::Trace::V1::ResourceSpans.new(
          resource: resource_from_env,
          instrumentation_library_spans: [
            Proto::Trace::V1::InstrumentationLibrarySpans.new(
              instrumentation_library: Proto::Common::V1::InstrumentationLibrary.new(
                name: "OpenTelemetry Crystal",
                version: VERSION,
              ),
              spans: spans.map(&.to_protobuf)
            ),
          ],
        )
      end

      def resource_from_env
        return nil if ENV["HONEYCOMB_DATASET"]?.nil?

        Proto::Resource::V1::Resource.new(
          attributes: [
            OpenTelemetry::Proto::Common::V1::KeyValue.new(
              key: "service.name",
              value: OpenTelemetry::Proto::Common::V1::AnyValue.new(ENV["HONEYCOMB_DATASET"])
            )
          ]
        )
      end
    end

    class Span
      alias PrimitiveAttributeValue = String | Int32 | Int64 | Float32 | Float64 | Time | Bool | Nil
      alias AttributeValue = PrimitiveAttributeValue | Hash(String, PrimitiveAttributeValue) | Array(PrimitiveAttributeValue)

      getter name : String
      getter id : Bytes = Random::Secure.random_bytes(8)
      getter trace_id : Bytes
      getter parent_id : Bytes?
      getter attributes = {} of String => AttributeValue
      getter started_at : Time?
      getter ended_at : Time?
      property kind : Proto::Trace::V1::Span::SpanKind
      property status : Proto::Trace::V1::Status?

      def initialize(@name, @trace_id, @parent_id, @kind : Proto::Trace::V1::Span::SpanKind)
      end

      def []=(key : String, value : AttributeValue)
        attributes[key] = value
      end

      def []?(key : String)
        attributes[key]?
      end

      def started!(now : Time = Time.utc)
        @started_at = now
      end

      def ended!(now : Time = Time.utc)
        @ended_at = now
      end

      def to_protobuf
        span = Proto::Trace::V1::Span.new(
          name: name,
          span_id: id,
          trace_id: trace_id,
          parent_span_id: parent_id,
          start_time_unix_nano: started_at_nanoseconds,
          end_time_unix_nano: ended_at_nanoseconds,
          kind: kind,
        )

        attributes.each do |key, value|
          span[key] = value
        end

        span
      end

      def populate_from_log_context(metadata = Log.context.metadata)
        metadata.each do |key, value|
          populate_field key.to_s, value.raw
        end
      end

      def populate_field(key : String, value : String | Int | Float | Bool | Nil | Time)
        self[key] = value
      end

      def populate_field(key : String, value : Array)
        self[key] = value.map(&.raw.as(PrimitiveAttributeValue)).as(Array(PrimitiveAttributeValue))
      end

      def populate_field(key : String, value : Hash)
        self[key] = value.transform_values(&.raw.as(PrimitiveAttributeValue)).as(Hash(String, PrimitiveAttributeValue))
      end

      private def started_at_nanoseconds
        if started_at = self.started_at
          (started_at - Time::UNIX_EPOCH).total_nanoseconds.to_u64
        end
      end

      private def ended_at_nanoseconds
        if ended_at = self.ended_at
          (ended_at - Time::UNIX_EPOCH).total_nanoseconds.to_u64
        end
      end
    end
  end
end

module OpenTelemetry
  module Proto
    module Trace
      module V1
        struct Span
          # Shorthand for adding an attribute to a span
          def []=(key : String, value)
            attributes = @attributes ||= [] of Common::V1::KeyValue
            if kv = attributes.find { |kv| kv.key == key }
              kv.value = Common::V1::AnyValue.new(value)
            else
              attributes << Common::V1::KeyValue.new(
                key: key,
                value: Common::V1::AnyValue.new(value),
              )
            end
            value
          end

          def [](key : String)
            if attributes = self.attributes
              attributes.each do |kv|
                return kv.unwrapped_value if kv.key == key
              end

              missing_attribute! key
            else
              missing_attribute! key
            end
          end

          def []?(key : String)
            if attributes = self.attributes
              attributes.each do |kv|
                return kv.unwrapped_value if kv.key == key
              end
            end

            nil
          end

          def missing_attribute!(key : String)
            raise KeyError.new("No attribute #{key.inspect} for span #{name.inspect}")
          end
        end
      end
    end

    module Common
      module V1
        struct AnyValue
          def initialize(@string_value : String)
          end

          def initialize(@bool_value : Bool)
          end

          def initialize(int_value : Int)
            @int_value = int_value.to_i64
          end

          def initialize(double_value : Float)
            @double_value = double_value.to_f64
          end

          def initialize(time_value : Time)
            @string_value = time_value.to_rfc3339(fraction_digits: 9)
          end

          def initialize(array_value : Array)
            @array_value = ArrayValue.new(array_value.map { |value|
              AnyValue.new(value)
            })
          end

          def initialize(kvlist_value : Hash)
            values = Array(KeyValue).new(initial_capacity: kvlist_value.size)
            kvlist_value.each do |key, value|
              values << KeyValue.new(key: key, value: AnyValue.new(value))
            end

            @kvlist_value = KeyValueList.new(values)
          end

          def initialize(@bytes_value : Bytes)
          end

          def initialize(nil_value : Nil)
          end

          def unwrapped_value
            string_value || bool_value || int_value || double_value || array_value || kvlist_value || bytes_value
          end
        end

        struct KeyValue
          def unwrapped_value
            if value = self.value
              value.unwrapped_value
            end
          end
        end
      end
    end
  end
end
