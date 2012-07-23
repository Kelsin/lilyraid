class RaidsController < ApplicationController
  before_filter(:load_raid, :only => [:edit, :update, :destroy, :show, :finalize])

  def index
    authorize! :read, Raid
    @old = params[:old]

    if @old
      @raids = Raid.where('raids.date < ?', Time.zone.now - 5.hours).order('raids.date desc')
    else
      @raids = Raid.where('raids.date >= ?', Time.zone.now - 5.hours).order('raids.date')
    end
  end

  def show
    authorize! :read, @raid
    @characters = @current_account.characters.active.not_signed_up_for(@raid)
    @tags = Tag.all
    @recent_raids = Raid.where('date < ?', @raid.date).limit(8).order('date desc').all.reverse
  end

  def finalize
    if @current_account == @raid.account or @current_account.admin
      @raid.finalized = !@raid.finalized
      @raid.save
    end

    finalize_log(@raid)

    respond_to do |format|
      format.html { redirect_to raid_url(@raid) }
    end
  end

  def edit
    authorize! :update, @raid
  end

  def update
    authorize! :update, @raid
    @raid.update_attributes(params[:raid])

    if @raid.save
      redirect_to raid_url(@raid)
    else
      flash[:error] = "Error saving raid"
      render :action => :edit
    end
  end

  def destroy
    if @current_account.can_edit?(@raid)
      @raid.destroy

      respond_to do |format|
        format.html { redirect_to raids_url }
        format.js { render :layout => false }
      end
    else
      flash[:error] = "You don't have permission to delete that raid"
      respond_to do |format|
        format.html { redirect_to raids_url }
        format.js { redirect_to raids_url }
      end
    end
  end

  def new
    authorize! :create, Raid
    @raid = Raid.new
    @raid.date = Time.zone.parse("Tomorrow 18h30") unless @raid.date
    @raid.number_of_slots = 10
  end

  def create
    authorize! :create, Raid

    # Create raid object
    @raid = Raid.new(params[:raid])
    @raid.account = current_user

    if @raid.save
      flash[:notice] = 'Raid saved!'
      redirect_to raid_url(@raid)
    else
      render :action => 'new'
    end
  end

  private

  def load_raid
    @raid = Raid.find(params[:id])
  end
end
