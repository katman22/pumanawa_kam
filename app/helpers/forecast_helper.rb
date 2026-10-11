module ForecastHelper
  def hourly_time_label(timestamp)
    value = timestamp.to_s
    parsed = DateTime.iso8601(value)
    offset = value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/i) ? "UTC#{parsed.strftime('%:z')}" : "offset not supplied"
    "#{parsed.strftime('%a %b %-d, %-I:%M %p')} (#{offset})"
  rescue ArgumentError, TypeError
    nil
  end

  def flowing_discussion_text(text)
    text.to_s.gsub(/\r\n?/, "\n").split(/\n[ \t]*\n+/).map do |paragraph|
      paragraph.gsub(/[ \t]*\n[ \t]*/, " ")
    end.join("\n\n")
  end
end
