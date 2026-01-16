require 'rails_helper'

RSpec.describe DailyUsage, type: :model do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
  let(:project) do
    Project.create!(
      name: "Test Project",
      slug: "test-project-#{Time.current.to_i}",
      status: "published",
      prompt_type: "is-it-spam",
      owner: user
    )
  end

  describe 'validations' do
    it 'requires a day' do
      daily_usage = DailyUsage.new(
        token_used: 100,
        user: user,
        project: project
      )
      expect(daily_usage).not_to be_valid
      expect(daily_usage.errors[:day]).to be_present
    end

    it 'requires uniqueness of day scoped to user and project' do
      DailyUsage.create!(
        day: Date.current,
        token_used: 100,
        user: user,
        project: project
      )

      duplicate = DailyUsage.new(
        day: Date.current,
        token_used: 200,
        user: user,
        project: project
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:day]).to be_present
    end

    it 'allows same day for different users' do
      user2 = User.create!(email_address: "test2@example.com", password: "password123")
      project2 = Project.create!(
        name: "Test Project 2",
        slug: "test-project-2-#{Time.current.to_i}",
        status: "published",
        prompt_type: "is-it-spam",
        owner: user2
      )

      DailyUsage.create!(
        day: Date.current,
        token_used: 100,
        user: user,
        project: project
      )

      daily_usage2 = DailyUsage.new(
        day: Date.current,
        token_used: 200,
        user: user2,
        project: project2
      )
      expect(daily_usage2).to be_valid
    end

    it 'allows same day for different projects' do
      project2 = Project.create!(
        name: "Test Project 2",
        slug: "test-project-2-#{Time.current.to_i}",
        status: "published",
        prompt_type: "is-it-spam",
        owner: user
      )

      DailyUsage.create!(
        day: Date.current,
        token_used: 100,
        user: user,
        project: project
      )

      daily_usage2 = DailyUsage.new(
        day: Date.current,
        token_used: 200,
        user: user,
        project: project2
      )
      expect(daily_usage2).to be_valid
    end
  end

  describe '.increment_tokens!' do
    it 'creates a new daily usage record if one does not exist' do
      expect {
        DailyUsage.increment_tokens!(
          day: Date.current,
          user: user,
          project: project,
          tokens: 150
        )
      }.to change { DailyUsage.count }.by(1)

      daily_usage = DailyUsage.last
      expect(daily_usage.day).to eq(Date.current)
      expect(daily_usage.user).to eq(user)
      expect(daily_usage.project).to eq(project)
      expect(daily_usage.token_used).to eq(150)
    end

    it 'increments token_used if a record already exists' do
      DailyUsage.create!(
        day: Date.current,
        token_used: 100,
        user: user,
        project: project
      )

      expect {
        DailyUsage.increment_tokens!(
          day: Date.current,
          user: user,
          project: project,
          tokens: 50
        )
      }.not_to change { DailyUsage.count }

      daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
      expect(daily_usage.token_used).to eq(150)
    end

    it 'handles multiple increments on the same day' do
      DailyUsage.increment_tokens!(
        day: Date.current,
        user: user,
        project: project,
        tokens: 50
      )

      DailyUsage.increment_tokens!(
        day: Date.current,
        user: user,
        project: project,
        tokens: 75
      )

      DailyUsage.increment_tokens!(
        day: Date.current,
        user: user,
        project: project,
        tokens: 25
      )

      daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
      expect(daily_usage.token_used).to eq(150)
    end

    it 'handles different days separately' do
      yesterday = Date.yesterday
      today = Date.current

      DailyUsage.increment_tokens!(
        day: yesterday,
        user: user,
        project: project,
        tokens: 100
      )

      DailyUsage.increment_tokens!(
        day: today,
        user: user,
        project: project,
        tokens: 200
      )

      expect(DailyUsage.count).to eq(2)
      expect(DailyUsage.find_by(day: yesterday, user: user, project: project).token_used).to eq(100)
      expect(DailyUsage.find_by(day: today, user: user, project: project).token_used).to eq(200)
    end

    it 'handles zero tokens gracefully' do
      DailyUsage.increment_tokens!(
        day: Date.current,
        user: user,
        project: project,
        tokens: 0
      )

      daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
      expect(daily_usage.token_used).to eq(0)
    end

    it 'returns the daily usage record' do
      result = DailyUsage.increment_tokens!(
        day: Date.current,
        user: user,
        project: project,
        tokens: 100
      )

      expect(result).to be_a(DailyUsage)
      expect(result.persisted?).to be true
      expect(result.token_used).to eq(100)
    end
  end

  describe '.monthly_total' do
    it 'returns 0 when there is no usage for the current month' do
      total = DailyUsage.monthly_total(user: user, project: project)
      expect(total).to eq(0)
    end

    it 'returns the total usage for the current month' do
      # Create usage for current month
      DailyUsage.create!(
        day: Date.current.beginning_of_month,
        token_used: 1000,
        user: user,
        project: project
      )
      DailyUsage.create!(
        day: Date.current,
        token_used: 2000,
        user: user,
        project: project
      )

      total = DailyUsage.monthly_total(user: user, project: project)
      expect(total).to eq(3000)
    end

    it 'only counts usage from the current month' do
      # Create usage from previous month (should not count)
      last_month = Date.current.beginning_of_month - 1.day
      DailyUsage.create!(
        day: last_month,
        token_used: 5000,
        user: user,
        project: project
      )

      # Create usage from current month
      DailyUsage.create!(
        day: Date.current,
        token_used: 1000,
        user: user,
        project: project
      )

      total = DailyUsage.monthly_total(user: user, project: project)
      expect(total).to eq(1000)
    end

    it 'only counts usage for the specified user and project' do
      # Create usage for different user
      other_user = User.create!(email_address: "other@example.com", password: "password123")
      other_project = Project.create!(
        name: "Other Project",
        slug: "other-project-#{Time.current.to_i}",
        status: "published",
        prompt_type: "is-it-spam",
        owner: other_user
      )

      DailyUsage.create!(
        day: Date.current,
        token_used: 5000,
        user: other_user,
        project: other_project
      )

      # Create usage for current user/project
      DailyUsage.create!(
        day: Date.current,
        token_used: 1000,
        user: user,
        project: project
      )

      total = DailyUsage.monthly_total(user: user, project: project)
      expect(total).to eq(1000)
    end

    it 'handles multiple days in the current month' do
      # Create usage for multiple days
      start_date = Date.current.beginning_of_month
      (0..5).each do |offset|
        DailyUsage.create!(
          day: start_date + offset.days,
          token_used: 100,
          user: user,
          project: project
        )
      end

      total = DailyUsage.monthly_total(user: user, project: project)
      expect(total).to eq(600)
    end
  end
end
