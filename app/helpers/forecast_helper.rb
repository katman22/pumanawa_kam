module ForecastHelper
  def flowing_discussion_text(text)
    text.to_s.gsub(/\r\n?/, "\n").split(/\n[ \t]*\n+/).map do |paragraph|
      paragraph.gsub(/[ \t]*\n[ \t]*/, " ")
    end.join("\n\n")
  end
end
