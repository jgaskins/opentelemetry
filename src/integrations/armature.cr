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
      if span = OpenTelemetry.current_span
        match_path = (span["http.route"] ||= "").as(String)
        match_path += "/#{match}"
        span["http.route"] = match_path
      end

      yield
    end
  end

  def on(capture : Symbol)
    previous_def do |value|
      if span = OpenTelemetry.current_span
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
        if span = OpenTelemetry.current_span
          match_path = (span["http.route"] ||= "").as(String)
          match_path += ".{{method.id}}"
          span["http.route"] = match_path
        end

        yield
      end
    end
  {% end %}
end
