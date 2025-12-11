# app/controllers/short_urls_controller.rb

class ShortUrlsController < ApplicationController
  before_action :authenticate_user!, except: [ :redirect, :check_availability, :stats, :track_click ]
  before_action :set_short_url, only: [ :destroy, :stats ]

  skip_before_action :verify_authenticity_token, only: [ :track_click ]

  def index
    @short_urls = current_user.short_urls.order(created_at: :desc)
  end

  def create
    @short_url = current_user.short_urls.new(short_url_params)

    duplicate_warning = check_duplicate_urls(@short_url)

    if @short_url.short_uri.blank?
      @short_url.short_uri = generate_unique_short_uri
    else
      unless valid_short_uri_format?(@short_url.short_uri)
        flash[:alert] = "Short code can only contain letters, numbers, hyphens, and underscores"
        redirect_to short_urls_path and return
      end

      if ShortUrl.exists?(short_uri: @short_url.short_uri)
        flash[:alert] = "This short code '#{@short_url.short_uri}' is already taken. Please try another one."
        redirect_to short_urls_path and return
      end
    end

    if @short_url.save
      success_message = "Short URL created successfully! Your link: #{request.base_url}/#{@short_url.short_uri}"
      success_message += "<br>⚠️ #{duplicate_warning}" if duplicate_warning.present?
      flash[:notice] = success_message.html_safe
      redirect_to short_urls_path
    else
      flash[:alert] = "" + @short_url.errors.full_messages.join(", ")
      redirect_to short_urls_path
    end
  end

  def destroy
    short_uri = @short_url.short_uri
    @short_url.destroy
    flash[:notice] = "Short URL '#{short_uri}' deleted successfully"
    redirect_to short_urls_path
  end

  def redirect
    @short_url = ShortUrl.find_by(short_uri: params[:short_uri])

    if @short_url
      @short_url.increment!(:click_count)

      render "redirect", layout: false
    else
      flash[:alert] = "Short URL not found"
      redirect_to root_path
    end
  end

  def track_click
    @short_url = ShortUrl.find_by(short_uri: params[:short_uri])

    unless @short_url
      Rails.logger.error("Track click: Short URL not found: #{params[:short_uri]}")
      render json: { success: false, error: "Short URL not found" }, status: :not_found
      return
    end

    begin
      if request.content_type&.include?("application/json")
        request.body.rewind
        parsed_params = JSON.parse(request.body.read)
      else
        parsed_params = params.to_unsafe_h
      end

      url_type = parsed_params["url_type"]
      redirected_url = parsed_params["redirected_url"]
      visitor_id = parsed_params["visitor_id"]

      Rails.logger.info("Track click attempt: short_uri=#{params[:short_uri]}, url_type=#{url_type}, visitor_id=#{visitor_id}")

      unless url_type.in?([ "url1", "url2" ]) && redirected_url.present?
        Rails.logger.error("Invalid parameters: url_type=#{url_type}, redirected_url=#{redirected_url}")
        render json: { success: false, error: "Invalid parameters" }, status: :unprocessable_entity
        return
      end

      tracking_result = UrlClick.track_click(
        short_url: @short_url,
        url_type: url_type,
        redirected_url: redirected_url,
        request: request,
        user_id: @short_url.user_id,
        visitor_id: visitor_id
      )

      if tracking_result
        Rails.logger.info("✓ Click tracked successfully in ClickHouse for #{params[:short_uri]}")
        render json: { success: true, message: "Click tracked successfully" }
      else
        Rails.logger.error("✗ ClickHouse tracking failed for #{params[:short_uri]}")
        render json: { success: false, error: "Tracking failed" }, status: :internal_server_error
      end

    rescue JSON::ParserError => e
      Rails.logger.error("JSON parse error: #{e.message}")
      render json: { success: false, error: "Invalid JSON" }, status: :bad_request
    rescue => e
      Rails.logger.error("Track click error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      render json: { success: false, error: "Internal server error" }, status: :internal_server_error
    end
  end

  def stats
    days = params[:days]&.to_i || 30
    @stats = UrlClick.comprehensive_stats(@short_url.id, days: days)
    @recent_clicks = UrlClick.recent_clicks(@short_url.id, limit: 50)

    respond_to do |format|
      format.html { render :stats }
      format.json { render json: @stats }
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
    if user_signed_in?
      @short_url = current_user.short_urls.find(params[:id])
    else
      @short_url = ShortUrl.find(params[:id])
    end
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

    existing_url1 = current_user.short_urls.where("url1 = ? OR url2 = ?", short_url.url1, short_url.url1)
    if existing_url1.exists?
      warnings << "URL 1 (#{short_url.url1}) is already being used in another short link"
    end

    if short_url.url2.present?
      existing_url2 = current_user.short_urls.where("url1 = ? OR url2 = ?", short_url.url2, short_url.url2)
      if existing_url2.exists?
        warnings << "URL 2 (#{short_url.url2}) is already being used in another short link"
      end
    end

    warnings.join(". ") if warnings.any?
  end
end
