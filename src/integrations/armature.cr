require "armature/route"
require "armature/session"

module Armature::Route
  def route(context)
    previous_def do |r, response, session|
      OpenTelemetry.trace self.class.name do |span|
        yield r, response, session
      end
    end
  end
end

class Armature::Route::Request
  def on(match : String)
    previous_def do
      if span = top_otel_http_span
        match_path = (span["http.route"] ||= "").as(String)
        match_path += "/#{match}"
        span["http.route"] = match_path
      end

      yield
    end
  end

  def on(capture : Symbol)
    previous_def do |value|
      if span = top_otel_http_span
        match_path = (span["http.route"] ||= "").as(String)
        match_path += "/:#{capture}"
        span["http.route"] = match_path
        span["match.value.#{capture.to_s}"] = value
      end

      yield value
    end
  end

  {% for method in %w[root get post put patch delete miss] %}
    def {{method.id}}
      previous_def do
        if span = top_otel_http_span
          match_path = (span["http.route"] ||= "").as(String)
          match_path += ".{{method.id}}"
          span["http.route"] = match_path
        end

        yield
      end
    end

    def {{method.id}}(match : String)
      previous_def do
        if span = top_otel_http_span
          match_path = (span["http.route"] ||= "").as(String)
          # The `.get` (or similar method) will precede this to emit
          # ".get(#{match})"
          match_path += "(#{match.inspect})"
          span["http.route"] = match_path
        end

        yield
      end
    end

    def {{method.id}}(capture : Symbol)
      previous_def do
        if span = top_otel_http_span
          match_path = (span["http.route"] ||= "").as(String)
          match_path += "(:#{match})"
          span["http.route"] = match_path
        end

        yield
      end
    end
  {% end %}

  private def top_otel_http_span
    OpenTelemetry
      .current_trace
      .spans
      .find { |s| s["http.flavor"]? }
  end
end

require "armature/cache"
class Armature::Cache::RedisStore
  def fetch(key : String, expires_in duration : Time::Span?, & : -> T) forall T
    OpenTelemetry.trace "cache.fetch" do |span|
      span["cache.key"] = key
      span["cache.hit"] = true
      span.kind = :client

      previous_def do
        span["cache.hit"] = false

        yield
      end
    end
  end
end

require "armature/redis_session"

module Armature
  class Session
    class RedisStore
      def load(key : String) : Hash(String, JSON::Any)
        OpenTelemetry.trace("Load") do |span|
          span["session.key"] = key

          previous_def
        end
      end

      def save(key : String, session : Session)
        return unless session.modified?

        OpenTelemetry.trace("Save") do |span|
          span["session.key"] = key

          previous_def
        end
      end
    end
  end
end
