class ShortUrlsController < ApplicationController
  before_action :authenticate_user!, except: [:redirect]
  before_action :set_short_url, only: [:show, :edit, :update, :destroy]

  # GET /short_urls
  def index
    @short_urls = current_user.short_urls.order(created_at: :desc)
  end

  # GET /short_urls/:id
  def show
  end

  # POST /short_urls
  def create
    @short_url = current_user.short_urls.new(short_url_params)
    
    # Generate random short_uri if not provided
    if @short_url.short_uri.blank?
      @short_url.short_uri = generate_unique_short_uri
    else
      # Validate custom short_uri
      unless valid_short_uri_format?(@short_url.short_uri)
        flash[:alert] = "Short code can only contain letters, numbers, hyphens, and underscores"
        redirect_to root_path and return
      end
      
      # Check if short_uri already exists
      if ShortUrl.exists?(short_uri: @short_url.short_uri)
        flash[:alert] = "This short code is already taken. Please try another one."
        redirect_to root_path and return
      end
    end

    if @short_url.save
      flash[:notice] = "Short URL created successfully! Your link: #{request.base_url}/#{@short_url.short_uri}"
      redirect_to short_urls_path
    else
      flash[:alert] = @short_url.errors.full_messages.join(", ")
      redirect_to root_path
    end
  end

  # GET /short_urls/:id/edit
  def edit
  end

  # PATCH/PUT /short_urls/:id
  def update
    if @short_url.update(short_url_params)
      flash[:notice] = "Short URL updated successfully"
      redirect_to short_urls_path
    else
      flash[:alert] = @short_url.errors.full_messages.join(", ")
      render :edit
    end
  end

  # DELETE /short_urls/:id
  def destroy
    @short_url.destroy
    flash[:notice] = "Short URL deleted successfully"
    redirect_to short_urls_path
  end

  # GET /:short_uri (redirect to actual URL)
  def redirect
    @short_url = ShortUrl.find_by(short_uri: params[:short_uri])
    
    if @short_url
      # Increment click count
      @short_url.increment!(:click_count)
      
      # Determine which URL to redirect to
      # If url2 is present, alternate between url1 and url2
      if @short_url.url2.present?
        # Odd clicks go to url1, even clicks go to url2
        target_url = @short_url.click_count.odd? ? @short_url.url1 : @short_url.url2
      else
        target_url = @short_url.url1
      end
      
      redirect_to target_url, allow_other_host: true
    else
      flash[:alert] = "Short URL not found"
      redirect_to root_path
    end
  end

  # API endpoint to check if short_uri is available
  def check_availability
    short_uri = params[:short_uri]
    
    if short_uri.blank?
      render json: { available: true }
    elsif !valid_short_uri_format?(short_uri)
      render json: { available: false, error: "Invalid format" }
    elsif ShortUrl.exists?(short_uri: short_uri)
      render json: { available: false, error: "Already taken" }
    else
      render json: { available: true }
    end
  end

  private

  def set_short_url
    @short_url = current_user.short_urls.find(params[:id])
  end

  def short_url_params
    params.require(:short_url).permit(:url1, :url2, :short_uri)
  end

  def generate_unique_short_uri
    loop do
      random_uri = SecureRandom.alphanumeric(5).downcase
      break random_uri unless ShortUrl.exists?(short_uri: random_uri)
    end
  end

  def valid_short_uri_format?(uri)
    uri.match?(/\A[a-zA-Z0-9_-]+\z/)
  end
end