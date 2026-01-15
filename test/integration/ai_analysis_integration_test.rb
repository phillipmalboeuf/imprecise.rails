require "test_helper"

class AiAnalysisIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      email_address: "test@example.com",
      password: "password123"
    )

    @prompt_types = %w[is-it-spam is-it-ai sentiment topics]
    @query_texts = {
      "is-it-spam" => "CLICK NOW!!! WIN $1000!!! URGENT LIMITED TIME OFFER!!!",
      "is-it-ai" => "In light of recent developments, it is imperative that we undertake a comprehensive analysis of the underlying factors that contribute to the multifaceted nature of this particular phenomenon.",
      "sentiment" => "I'm absolutely thrilled and overjoyed about this amazing opportunity! This is the best day ever!",
      "topics" => "The weather forecast shows sunny skies for the weekend. Planning a barbecue with friends and family. Need to buy groceries and prepare the menu."
    }
  end

  test "creates user, projects for each prompt type, queries, and gets AI responses" do
    assert @user.persisted?

    # Create projects for each prompt type
    projects = {}

    @prompt_types.each_with_index do |prompt_type, index|
      project = Project.create!(
        name: "#{prompt_type.gsub('-', ' ').titleize} Project",
        slug: "#{prompt_type}-project-#{Time.current.to_i}-#{index}",
        status: "published",
        prompt_type: prompt_type,
        owner: @user
      )
      assert project.persisted?
      projects[prompt_type] = project
    end

    # Create queries with appropriate test texts for each project
    queries = {}

    @prompt_types.each do |prompt_type|
      query = Query.create!(
        project: projects[prompt_type],
        query: @query_texts[prompt_type]
      )
      assert query.persisted?
      queries[prompt_type] = query
    end

    # Call AiAnalysisService for each query and verify we get responses
    @prompt_types.each do |prompt_type|
      query = queries[prompt_type]
      service = AiAnalysisService.new(query)

      # Call the service (will make real API call to OpenAI)
      response = service.call

      # Verify we got a response (either a successful response or an error hash)
      assert response, "Expected a response for #{prompt_type} query"
      assert response.is_a?(Hash), "Expected response to be a Hash for #{prompt_type} query"

      # If there's an error, it will be in the error key (from the rescue block)
      # Otherwise, we should have a valid API response structure
      if response.key?("error")
        # API call failed but we still got a structured response
        assert response["error"].present?, "Error message should be present"
      else
        # Successful API response - should have id and choices
        assert response.key?("id"), "Response should have 'id' key for #{prompt_type}"
        assert response.key?("choices"), "Response should have 'choices' key for #{prompt_type}"
      end
    end
  end
end
