class ProjectsController < ApplicationController
  def index
    @projects = Current.user.projects.includes(:owner)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Current.user.projects.build(project_params)

    if @project.save
      redirect_to projects_path, notice: "Project created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

    def project_params
      params.require(:project).permit(:name, :slug, :status, :prompt_type)
    end
end
