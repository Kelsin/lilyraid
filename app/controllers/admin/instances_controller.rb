class Admin::InstancesController < ApplicationController
  before_filter :require_admin

  def index
    authorize! :read, Instance
    @active = Instance.active.all
    @inactive = Instance.inactive.all
    @new_instance = Instance.new
  end

  def edit
    @instance = Instance.find(params[:id])
    authorize! :update, @instance
  end

  def update
    @instance = Instance.find(params[:id])
    authorize! :update, @instance

    if @instance.update_attributes(params[:instance])
      redirect_to admin_instances_url
    else
      render :action => :edit
    end
  end

  def create
    @new_instance = Instance.new(params[:instance])
    authorize! :create, @instance

    if @new_instance.save
      redirect_to admin_instances_url
    else
      @active = Instance.active.all
      @inactive = Instance.inactive.all
      render :action => :index
    end
  end

  def destroy
    @instance = Instance.find(params[:id])
    authorize! :destroy, @instance
    @instance.destroy
    redirect_to admin_instances_url
  end
end
