class AiAnalysisService
  def initialize(query)
    @query = query
  end

  def call
    client = OpenAI::Client.new(
      api_key: api_key,
      base_url: "https://api.x.ai/v1"
    )

    response = client.chat.completions.create(
      messages:[
        {
          role: "system",
          content: "You are Imprecise Analysis, a system that determines if a message is spam or not.",
        },
        {
          role: "user",
          content: "Would you consider the following message to be spam? (Answer with only a yes or no and add a percentage of confidence as purely a number) : #{@query.query}",
        },
      ],
      model: "grok-3-mini-fast"
    )

    response
  rescue StandardError => e
    Rails.logger.error("AI Analysis Service Error: #{e.message}")
    { error: e.message }
  end

  private

  def api_key
    Rails.application.credentials.openai.xaikey
  end
end
