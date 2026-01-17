# typed: true
# frozen_string_literal: true

class Query < ApplicationRecord
  belongs_to :project

  validates :query, presence: true

  # Check if this query would exceed the monthly token limit
  # Returns error message string if limit would be exceeded, nil otherwise
  def monthly_token_limit_error_message
    project_owner = project&.owner
    return nil unless project_owner

    estimated_tokens = AiAnalysisService.new(self).estimate_prompt_tokens
    current_monthly_usage = DailyUsage.monthly_total(user: project_owner, project: project)

    if current_monthly_usage + estimated_tokens > ApplicationController::MAX_MONTHLY_TOKENS
      "Monthly token limit exceeded. Current usage: #{current_monthly_usage}, Estimated for this query: #{estimated_tokens}, Limit: #{ApplicationController::MAX_MONTHLY_TOKENS}."
    end
  end

  # Run AI analysis and save response/answer
  # Returns the AI response object
  def run_ai_analysis!
    ai_response = AiAnalysisService.new(self).call
    
    if ai_response.present?
      # Extract answer from first choice's message content
      # Split by commas if present, otherwise by spaces, and make lowercase
      answer = if ai_response.respond_to?(:choices) && ai_response.choices.first
        content = ai_response.choices.first.message.content
        if content
          terms = if content.include?(',')
            content.split(',').map(&:strip)
          else
            content.split(/\s+/)
          end
          
          terms.map(&:downcase).reject(&:empty?)
        else
          []
        end
      else
        []
      end
      
      # Store the response in a format that matches the controller's expectations
      response_data = if ai_response.is_a?(Hash)
        ai_response
      elsif ai_response.respond_to?(:to_h)
        ai_response.to_h
      else
        { content: ai_response }
      end
      
      update(response: response_data, answer: answer)
      
      # Track daily usage if we have a valid AI response with usage information
      if ai_response.respond_to?(:usage)
        project_owner = project&.owner
        if project_owner
          usage = ai_response.usage
          if usage && usage.respond_to?(:prompt_tokens)
            prompt_tokens = usage.prompt_tokens || 0
            if prompt_tokens > 0
              DailyUsage.increment_tokens!(
                day: Date.current,
                user: project_owner,
                project: project,
                tokens: prompt_tokens
              )
            end
          end
        end
      end
    end
    
    ai_response
  end
end

