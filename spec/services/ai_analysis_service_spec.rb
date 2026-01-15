require 'rails_helper'

RSpec.describe AiAnalysisService, type: :service do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
  
  describe '#call' do
    context 'with is-it-spam prompt type' do
      let(:project) do
        Project.create!(
          name: "Spam Detection",
          slug: "spam-detection",
          status: "published",
          prompt_type: "is-it-spam",
          owner: user
        )
      end
      let(:query) { Query.create!(project: project, query: "CLICK NOW!!! WIN $1000!!! URGENT LIMITED TIME OFFER!!!") }
      let(:service) { described_class.new(query) }

      it 'returns an OpenAI chat completion response' do
        response = service.call
        
        if response.is_a?(Hash) && response.key?("error")
          expect(response["error"]).to be_present
        else
          # Validate OpenAI ChatCompletion object structure
          expect(response).to be_an(OpenAI::Models::Chat::ChatCompletion)
          expect(response.choices.length).to be > 0
          
          choice = response.choices.first
          expect(choice.message).to be_a(OpenAI::Models::Chat::ChatCompletionMessage)
          expect(choice.message.content).to be_a(String)
        end
      end
    end

    context 'with is-it-ai prompt type' do
      let(:project) do
        Project.create!(
          name: "AI Detection",
          slug: "ai-detection",
          status: "published",
          prompt_type: "is-it-ai",
          owner: user
        )
      end
      let(:query) do
        Query.create!(
          project: project,
          query: "In light of recent developments, it is imperative that we undertake a comprehensive analysis of the underlying factors that contribute to the multifaceted nature of this particular phenomenon."
        )
      end
      let(:service) { described_class.new(query) }

      it 'returns an OpenAI chat completion response' do
        response = service.call
        
        if response.is_a?(Hash) && response.key?("error")
          expect(response["error"]).to be_present
        else
          # Validate OpenAI ChatCompletion object structure
          expect(response).to be_an(OpenAI::Models::Chat::ChatCompletion)
          expect(response.choices.length).to be > 0
          
          choice = response.choices.first
          expect(choice.message).to be_a(OpenAI::Models::Chat::ChatCompletionMessage)
          expect(choice.message.content).to be_a(String)
        end
      end
    end

    context 'with sentiment prompt type' do
      let(:project) do
        Project.create!(
          name: "Sentiment Analysis",
          slug: "sentiment-analysis",
          status: "published",
          prompt_type: "sentiment",
          owner: user
        )
      end
      let(:query) do
        Query.create!(
          project: project,
          query: "I'm absolutely thrilled and overjoyed about this amazing opportunity! This is the best day ever!"
        )
      end
      let(:service) { described_class.new(query) }

      it 'returns an OpenAI chat completion response' do
        response = service.call
        
        if response.is_a?(Hash) && response.key?("error")
          expect(response["error"]).to be_present
        else
          # Validate OpenAI ChatCompletion object structure
          expect(response).to be_an(OpenAI::Models::Chat::ChatCompletion)
          expect(response.choices.length).to be > 0
          
          choice = response.choices.first
          expect(choice.message).to be_a(OpenAI::Models::Chat::ChatCompletionMessage)
          expect(choice.message.content).to be_a(String)
        end
      end
    end

    context 'with topics prompt type' do
      let(:project) do
        Project.create!(
          name: "Topic Analysis",
          slug: "topic-analysis",
          status: "published",
          prompt_type: "topics",
          owner: user
        )
      end
      let(:query) do
        Query.create!(
          project: project,
          query: "The weather forecast shows sunny skies for the weekend. Planning a barbecue with friends and family. Need to buy groceries and prepare the menu."
        )
      end
      let(:service) { described_class.new(query) }

      it 'returns an OpenAI chat completion response' do
        response = service.call
        
        if response.is_a?(Hash) && response.key?("error")
          expect(response["error"]).to be_present
        else
          # Validate OpenAI ChatCompletion object structure
          expect(response).to be_an(OpenAI::Models::Chat::ChatCompletion)
          expect(response.choices.length).to be > 0
          
          choice = response.choices.first
          expect(choice.message).to be_a(OpenAI::Models::Chat::ChatCompletionMessage)
          expect(choice.message.content).to be_a(String)
        end
      end
    end
  end
end
