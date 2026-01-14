# frozen_string_literal: true

module Types
  class PromptTypeEnum < Types::BaseEnum
    description "Type of prompt for analysis"
    value "IS_IT_SPAM", value: "is-it-spam", description: "Spam detection analysis"
    value "IS_IT_AI", value: "is-it-ai", description: "AI detection analysis"
    value "TOPICS", value: "topics", description: "Topic extraction analysis"
    value "SENTIMENT", value: "sentiment", description: "Sentiment analysis"
  end
end
