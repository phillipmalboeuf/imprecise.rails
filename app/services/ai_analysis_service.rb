# typed: true
# frozen_string_literal: true

class AiAnalysisService
  extend T::Sig

  sig { params(query: Query).void }
  def initialize(query)
    @query = query
  end

  def call
    client = OpenAI::Client.new(
      api_key: api_key,
      base_url: "https://api.x.ai/v1"
    )

    response = client.chat.completions.create(
      messages: build_messages,
      model: "grok-3-mini-fast"
    )

    response
  rescue StandardError => e
    Rails.logger.error("AI Analysis Service Error: #{e.message}")
    { error: e.message }
  end

  # Estimate the number of tokens that will be used for the prompt
  # Uses a simple approximation: ~4 characters per token (common for English text)
  # This is a rough estimate and may not be exact, but should be close enough for quota checking
  def estimate_prompt_tokens
    messages = build_messages
    total_chars = messages.sum do |message|
      # Count characters in the content
      content = message[:content] || ""
      content.length
    end
    
    # Divide by 4 to get approximate token count (4 chars per token is a common approximation)
    (total_chars / 4.0).ceil
  end

  private

  def api_key
    Rails.application.credentials.openai.xaikey
  end

  def build_messages
    prompt_type = T.must(@query.project).prompt_type

    case prompt_type
    when "is-it-spam"
      [
        {
          role: "system",
          content: "You are Imprecise Analysis, a system that determines if a message is spam or not.",
        },
        {
          role: "user",
          content: "Would you consider the following message to be spam? (Answer with only a yes or no and add a percentage of confidence as purely a number) : #{@query.query}",
        },
      ]
    when "is-it-ai"
      [
        {
          role: "system",
          content: "You are Imprecise Analysis, a system that determines if a message is ai-generated or not.",
        },
        {
          role: "user",
          content: "Would you consider the following message to be ai-generated? (Answer with only a yes or no and add a percentage of confidence as purely a number) : #{@query.query}",
        },
      ]
    when "sentiment"
      [
        {
          role: "system",
          content: "You are Imprecise Analysis, a system that analyses sentiment in a message, with only a words list of a maximum length of 10, formatted in a comma separated list.",
        },
        {
          role: "user",
          content: "What is the sentiment of the following message? Answer with a positive, negative or neutral, as well as a few more words to describe the sentiment. : #{@query.query}",
        },
      ]
    when "topics"
      [
        {
          role: "system",
          content: "You are Imprecise Analysis, a system that analyses the different topics of a message, with only a list of a maximum length of 10, formatted in a comma separated list.",
        },
        {
          role: "user",
          content: "What are the topics addressed in the following message? : #{@query.query}",
        },
      ]
    end
  end
end
