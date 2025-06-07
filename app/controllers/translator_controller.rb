class TranslatorController < ApplicationController

  AVAILABLE_LANGUAGES = [
    %w[Spanish es],
    %w[French fr],
    %w[Farsi fa],
    %w[Chinese (Simplified), zh],
    %w[Māori mi]
  ]

  def index
    @available_languages = AVAILABLE_LANGUAGES
  end

  def show
    @language = params[:lang]
    @translation = params[:text]
  end

  def create
    input_text = params[:text]
    @target_languages = params[:languages]
    translated_results = @target_languages.map do |lang_code|
      translation = translate_text(input_text, lang_code)
      [lang_code, translation]
    end.to_h

    @input_text = input_text
    @translated_results = translated_results
    @layout_mode = params[:layout] || "column"
    render :translations, locals: { translated_results: @translated_results, input_text: @input_text, layout_mode: @layout_mode, languages: @target_languages }
  end

  private

  def translate_text(text, target_language)
    uri = URI("https://translation.googleapis.com/language/translate/v2")

    response = Net::HTTP.post_form(uri, {
      q: text,
      target: target_language,
      format: "text",
      key: ENV["GOOGLE_API_KEY"]
    })

    json = JSON.parse(response.body)
    json.dig("data", "translations", 0, "translatedText") || "Error translating"
  end
end

