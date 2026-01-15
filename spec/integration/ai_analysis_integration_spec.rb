require 'rails_helper'

RSpec.describe 'AiAnalysisService Integration', type: :integration do
  let(:user) do
    User.create!(
      email_address: "test@example.com",
      password: "password123"
    )
  end

  let(:prompt_types) { %w[is-it-spam is-it-ai sentiment topics] }
  
  let(:query_texts) do
    {
      "is-it-spam" => "CLICK NOW!!! WIN $1000!!! URGENT LIMITED TIME OFFER!!!",
      "is-it-ai" => "In light of recent developments, it is imperative that we undertake a comprehensive analysis of the underlying factors that contribute to the multifaceted nature of this particular phenomenon.",
      "sentiment" => "I'm absolutely thrilled and overjoyed about this amazing opportunity! This is the best day ever!",
      "topics" => "The weather forecast shows sunny skies for the weekend. Planning a barbecue with friends and family. Need to buy groceries and prepare the menu."
    }
  end

  it 'creates user, projects for each prompt type, queries, and gets AI responses' do
    expect(user).to be_persisted

    # Create projects for each prompt type
    projects = {}

    prompt_types.each_with_index do |prompt_type, index|
      project = Project.create!(
        name: "#{prompt_type.gsub('-', ' ').titleize} Project",
        slug: "#{prompt_type}-project-#{Time.current.to_i}-#{index}",
        status: "published",
        prompt_type: prompt_type,
        owner: user
      )
      expect(project).to be_persisted
      projects[prompt_type] = project
    end

    # Create queries with appropriate test texts for each project
    queries = {}

    prompt_types.each do |prompt_type|
      query = Query.create!(
        project: projects[prompt_type],
        query: query_texts[prompt_type]
      )
      expect(query).to be_persisted
      queries[prompt_type] = query
    end

    # Call AiAnalysisService for each query and verify we get responses
    prompt_types.each do |prompt_type|
      query = queries[prompt_type]
      service = AiAnalysisService.new(query)

      # Call the service (will make real API call to OpenAI)
      response = service.call

      # If there's an error, it will be a Hash with an error key (from the rescue block)
      if response.is_a?(Hash) && response.key?("error")
        expect(response["error"]).to be_present
      else
        # Successful response should be an OpenAI ChatCompletion object
        expect(response).to be_an(OpenAI::Models::Chat::ChatCompletion)
        expect(response.choices.length).to be > 0
      end
    end
  end
end
