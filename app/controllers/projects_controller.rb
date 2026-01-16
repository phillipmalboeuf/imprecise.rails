class ProjectsController < ApplicationController
  def index
    @projects = Current.user.projects.includes(:owner)
  end

  def show
    @project = Current.user.projects.find_by!(slug: params[:slug])
    @queries = @project.queries.order(created_at: :desc).limit(10)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Current.user.projects.build(project_params)

    if @project.save
      redirect_to projects_path, notice: "Project created successfully! API Key: #{@project.decrypted_apikey}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @project = Current.user.projects.find_by!(slug: params[:slug])
  end

  def update
    @project = Current.user.projects.find_by!(slug: params[:slug])

    if @project.update(project_params)
      redirect_to @project, notice: "Project updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate_apikey
    @project = Current.user.projects.find_by!(slug: params[:slug])

    @project.regenerate_apikey!
    redirect_to projects_path, notice: "API Key regenerated successfully! New API Key: #{@project.decrypted_apikey}"
  end

  private

    def project_params
      params.require(:project).permit(:name, :slug, :status, :prompt_type)
    end
end
