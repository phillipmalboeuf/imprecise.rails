# typed: true
# frozen_string_literal: true

class DailyUsagesController < ApplicationController
  def index
    @user = Current.user
    @projects = @user.projects.order(:name)
    
    # Get the current month's date range
    @start_date = Date.current.beginning_of_month
    @end_date = Date.current.end_of_month
    @days = (@start_date..@end_date).to_a
    
    # Preload daily usages for the current month for all user's projects
    daily_usages = DailyUsage.where(
      user: @user,
      project: @projects,
      day: @start_date..@end_date
    ).includes(:project)
    
    # Build a hash for quick lookup: [day, project_id] => token_used
    @usage_map = daily_usages.each_with_object({}) do |usage, hash|
      hash[[usage.day, usage.project_id]] = usage.token_used
    end
    
    # Calculate totals per day
    @daily_totals = {}
    @days.each do |day|
      @daily_totals[day] = @projects.sum { |project| @usage_map[[day, project.id]] || 0 }
    end
    
    # Calculate totals per project
    @project_totals = {}
    @projects.each do |project|
      @project_totals[project.id] = @days.sum { |day| @usage_map[[day, project.id]] || 0 }
    end
    
    # Calculate grand total
    @grand_total = @days.sum { |day| @daily_totals[day] }
  end
end
