# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Query, type: :model do
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
  let(:query) { Query.create!(project: project, query: "Is this spam?") }

  describe '#run_ai_analysis!' do
    context 'with AI response containing usage information' do
      let(:mock_usage) do
        double('Usage', prompt_tokens: 150, completion_tokens: 50, total_tokens: 200)
      end

      let(:mock_ai_response) do
        double('ChatCompletion',
          usage: mock_usage,
          choices: [double('Choice', message: double('Message', content: 'Test response'))],
          respond_to?: true
        )
      end

      before do
        allow(mock_ai_response).to receive(:respond_to?).with(:choices).and_return(true)
        allow(mock_ai_response).to receive(:respond_to?).with(:usage).and_return(true)
        allow(mock_ai_response).to receive(:respond_to?).with(:to_h).and_return(true)
        allow(mock_ai_response).to receive(:respond_to?).with(:empty?).and_return(true)
        allow(mock_ai_response).to receive(:empty?).and_return(false)
        allow(mock_ai_response).to receive(:to_h).and_return({ id: 'test-id' })
        allow_any_instance_of(AiAnalysisService).to receive(:call).and_return(mock_ai_response)
      end

      it 'creates a daily usage record when a query is made' do
        expect {
          query.run_ai_analysis!
        }.to change { DailyUsage.count }.by(1)

        daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
        expect(daily_usage).to be_present
        expect(daily_usage.token_used).to eq(150)
      end

      it 'increments token_used for existing daily usage record' do
        DailyUsage.create!(
          day: Date.current,
          token_used: 100,
          user: user,
          project: project
        )

        expect {
          query.run_ai_analysis!
        }.not_to change { DailyUsage.count }

        daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
        expect(daily_usage.token_used).to eq(250)
      end

      it 'tracks tokens correctly for multiple queries on the same day' do
        query.run_ai_analysis!
        
        query2 = Query.create!(project: project, query: "Another query")
        query2.run_ai_analysis!

        daily_usage = DailyUsage.find_by(day: Date.current, user: user, project: project)
        expect(daily_usage.token_used).to eq(300) # 150 + 150
      end
    end

    context 'with AI response error' do
      let(:error_response) { { error: "API Error" } }

      before do
        allow_any_instance_of(AiAnalysisService).to receive(:call).and_return(error_response)
      end

      it 'does not create a daily usage record when AI response is an error' do
        expect {
          query.run_ai_analysis!
        }.not_to change { DailyUsage.count }
      end
    end

    context 'answer formatting' do
      let(:mock_usage) do
        double('Usage', prompt_tokens: 150)
      end

      before do
        allow(mock_usage).to receive(:respond_to?).with(:prompt_tokens).and_return(true)
        allow_any_instance_of(AiAnalysisService).to receive(:call).and_return(mock_ai_response)
      end

      context 'with comma-separated content' do
        let(:mock_ai_response) do
          double('ChatCompletion',
            usage: mock_usage,
            choices: [double('Choice', message: double('Message', content: 'Positive, Happy, Excited'))],
            respond_to?: true
          )
        end

        before do
          allow(mock_ai_response).to receive(:respond_to?).with(:choices).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:usage).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:to_h).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:empty?).and_return(true)
          allow(mock_ai_response).to receive(:empty?).and_return(false)
          allow(mock_ai_response).to receive(:to_h).and_return({})
        end

        it 'splits content by commas and converts to lowercase' do
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['positive', 'happy', 'excited'])
        end

        it 'strips whitespace from comma-separated values' do
          mock_choice = double('Choice', message: double('Message', content: 'Positive , Happy , Excited'))
          allow(mock_ai_response).to receive(:choices).and_return([mock_choice])
          
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['positive', 'happy', 'excited'])
        end
      end

      context 'with space-separated content' do
        let(:mock_ai_response) do
          double('ChatCompletion',
            usage: mock_usage,
            choices: [double('Choice', message: double('Message', content: 'The weather is nice'))],
            respond_to?: true
          )
        end

        before do
          allow(mock_ai_response).to receive(:respond_to?).with(:choices).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:usage).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:to_h).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:empty?).and_return(true)
          allow(mock_ai_response).to receive(:empty?).and_return(false)
          allow(mock_ai_response).to receive(:to_h).and_return({})
        end

        it 'splits content by spaces and converts to lowercase' do
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['the', 'weather', 'is', 'nice'])
        end

        it 'handles multiple spaces correctly' do
          mock_choice = double('Choice', message: double('Message', content: 'The   weather    is  nice'))
          allow(mock_ai_response).to receive(:choices).and_return([mock_choice])
          
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['the', 'weather', 'is', 'nice'])
        end
      end

      context 'with mixed case content' do
        let(:mock_ai_response) do
          double('ChatCompletion',
            usage: mock_usage,
            choices: [double('Choice', message: double('Message', content: 'Positive, HAPPY, Excited'))],
            respond_to?: true
          )
        end

        before do
          allow(mock_ai_response).to receive(:respond_to?).with(:choices).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:usage).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:to_h).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:empty?).and_return(true)
          allow(mock_ai_response).to receive(:empty?).and_return(false)
          allow(mock_ai_response).to receive(:to_h).and_return({})
        end

        it 'converts all terms to lowercase' do
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['positive', 'happy', 'excited'])
        end
      end

      context 'with empty strings' do
        let(:mock_ai_response) do
          double('ChatCompletion',
            usage: mock_usage,
            choices: [double('Choice', message: double('Message', content: 'Positive, , Happy,  , Excited'))],
            respond_to?: true
          )
        end

        before do
          allow(mock_ai_response).to receive(:respond_to?).with(:choices).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:usage).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:to_h).and_return(true)
          allow(mock_ai_response).to receive(:respond_to?).with(:empty?).and_return(true)
          allow(mock_ai_response).to receive(:empty?).and_return(false)
          allow(mock_ai_response).to receive(:to_h).and_return({})
        end

        it 'removes empty strings from the result' do
          query.run_ai_analysis!
          
          expect(query.answer).to eq(['positive', 'happy', 'excited'])
        end
      end
    end
  end
end
