class ShortUrlsController < ApplicationController
before_action :authenticate_user!, except: [ :redirect, :check_availability ]
  before_action :set_short_url, only: [ :destroy ]

  # GET /short_urls
  def index
    @short_urls = current_user.short_urls.order(created_at: :desc)
  end

  # POST /short_urls
  def create
    @short_url = current_user.short_urls.new(short_url_params)

    # Check for duplicate URLs (warning, not blocking)
    duplicate_warning = check_duplicate_urls(@short_url)

    # Generate random short_uri if not provided
    if @short_url.short_uri.blank?
      @short_url.short_uri = generate_unique_short_uri
    else
      # Validate custom short_uri format
      unless valid_short_uri_format?(@short_url.short_uri)
        flash[:alert] = "❌ Short code can only contain letters, numbers, hyphens, and underscores"
        redirect_to short_urls_path and return
      end

      # Check if short_uri already exists
      if ShortUrl.exists?(short_uri: @short_url.short_uri)
        flash[:alert] = "❌ This short code '#{@short_url.short_uri}' is already taken. Please try another one."
        redirect_to short_urls_path and return
      end
    end

    if @short_url.save
      success_message = "✅ Short URL created successfully! Your link: #{request.base_url}/#{@short_url.short_uri}"
      success_message += "<br>⚠️ #{duplicate_warning}" if duplicate_warning.present?
      flash[:notice] = success_message.html_safe
      redirect_to short_urls_path
    else
      flash[:alert] = "❌ " + @short_url.errors.full_messages.join(", ")
      redirect_to short_urls_path
    end
  end

  # DELETE /short_urls/:id
  def destroy
    short_uri = @short_url.short_uri
    @short_url.destroy
    flash[:notice] = "🗑️ Short URL '#{short_uri}' deleted successfully"
    redirect_to short_urls_path
  end

  # GET /:short_uri (redirect to actual URL using client-side localStorage)
  def redirect
    @short_url = ShortUrl.find_by(short_uri: params[:short_uri])

    if @short_url
      # Increment total click count (for statistics)
      @short_url.increment!(:click_count)

      # Render a page that uses localStorage to determine which URL to redirect to
      render "redirect", layout: false
    else
      flash[:alert] = "❌ Short URL not found"
      redirect_to root_path
    end
  end

def check_availability
  short_uri = params[:short_uri].to_s.strip.downcase

  if short_uri.blank?
    render json: { available: true, message: "" }
    return
  end

  unless valid_short_uri_format?(short_uri)
    render json: {
      available: false,
      message: "Invalid format. Only letters, numbers, hyphens, and underscores allowed."
    }
    return
  end

  if ShortUrl.exists?(short_uri: short_uri)
    render json: {
      available: false,
      message: "This short code is already taken. Please try another one."
    }
  else
    render json: {
      available: true,
      message: "This short code is available! ✓"
    }
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

  def check_duplicate_urls(short_url)
    warnings = []

    # Check if URL1 is already used by this user
    existing_url1 = current_user.short_urls.where("url1 = ? OR url2 = ?", short_url.url1, short_url.url1)
    if existing_url1.exists?
      warnings << "URL 1 (#{short_url.url1}) is already being used in another short link"
    end

    # Check if URL2 is already used by this user (if provided)
    if short_url.url2.present?
      existing_url2 = current_user.short_urls.where("url1 = ? OR url2 = ?", short_url.url2, short_url.url2)
      if existing_url2.exists?
        warnings << "URL 2 (#{short_url.url2}) is already being used in another short link"
      end
    end

    warnings.join(". ") if warnings.any?
  end
end
