# typed: true
# frozen_string_literal: true

class DailyUsage < ApplicationRecord
  belongs_to :user
  belongs_to :project

  validates :day, presence: true
  validates :token_used, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :day, uniqueness: { scope: [:user_id, :project_id] }

  # Find or create a daily usage record for the given day, user, and project
  # and increment the token_used by the specified amount
  def self.increment_tokens!(day:, user:, project:, tokens:)
    daily_usage = find_or_initialize_by(day: day, user: user, project: project)
    daily_usage.token_used += tokens
    daily_usage.save!
    daily_usage
  end

  # Get the total token usage for a user and project in the current month
  def self.monthly_total(user:, project:)
    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month
    
    where(
      user: user,
      project: project,
      day: start_date..end_date
    ).sum(:token_used)
  end
end
