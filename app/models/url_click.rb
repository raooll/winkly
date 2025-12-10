# app/models/url_click.rb

class UrlClick < ClickhouseRecord
  self.table_name = "url_clicks"

  # Track a URL click with all necessary information
  def self.track_click(short_url:, url_type:, redirected_url:, request:, user_id: nil)
    require "net/http"
    require "uri"

    config = get_clickhouse_config
    unless config
      Rails.logger.error("ClickHouse config not available")
      puts "ERROR: ClickHouse config not available" # Debug output
      return false
    end

    click_id = generate_unique_id
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S")

    # Parse user agent
    user_agent = request.user_agent || "Unknown"
    browser_info = parse_user_agent(user_agent)

    # Get IP and location info
    ip_address = request.remote_ip
    location_info = get_location_info(ip_address)

    # Parse referrer
    referrer = request.referer
    referrer_domain = referrer ? URI.parse(referrer).host : nil rescue nil

    query = <<~SQL
      INSERT INTO url_clicks (
        id, short_url_id, tracking_id, short_uri, redirected_to_url, url_type,
        user_id, session_id,
        user_agent, browser, browser_version, device_type, os, os_version,
        ip_address, country, city, region,
        referrer, referrer_domain,
        clicked_at, created_at
      ) VALUES (
        #{click_id},
        #{short_url.id},
        '#{escape_string(short_url.tracking_id)}',
        '#{escape_string(short_url.short_uri)}',
        '#{escape_string(redirected_url)}',
        '#{url_type}',
        #{user_id || 'NULL'},
        #{request.session_options[:id] ? "'#{escape_string(request.session_options[:id])}'" : 'NULL'},
        '#{escape_string(user_agent)}',
        '#{escape_string(browser_info[:browser])}',
        '#{escape_string(browser_info[:version])}',
        '#{escape_string(browser_info[:device_type])}',
        '#{escape_string(browser_info[:os])}',
        '#{escape_string(browser_info[:os_version])}',
        '#{escape_string(ip_address)}',
        '#{escape_string(location_info[:country])}',
        '#{escape_string(location_info[:city])}',
        '#{escape_string(location_info[:region])}',
        #{referrer ? "'#{escape_string(referrer)}'" : 'NULL'},
        #{referrer_domain ? "'#{escape_string(referrer_domain)}'" : 'NULL'},
        '#{timestamp}',
        '#{timestamp}'
      )
    SQL

    execute_raw(config, query)
    true
  rescue => e
    Rails.logger.error("ClickHouse URL click tracking failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end

  # Analytics Methods

  # Get total clicks for a short URL
  def self.total_clicks(short_url_id)
    where("short_url_id = ?", short_url_id).count
  end

  # Get clicks by URL type (url1 vs url2)
  def self.clicks_by_url_type(short_url_id)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        url_type,
        count() as count,
        uniq(ip_address) as unique_visitors
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
      GROUP BY url_type
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse clicks_by_url_type failed: #{e.message}")
    []
  end

  # Get clicks over time (daily)
  def self.clicks_over_time(short_url_id, days: 30)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        toDate(clicked_at) as date,
        url_type,
        count() as clicks,
        uniq(ip_address) as unique_visitors
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
        AND clicked_at >= today() - #{days}
      GROUP BY date, url_type
      ORDER BY date DESC
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse clicks_over_time failed: #{e.message}")
    []
  end

  # Get geographic distribution
  def self.geographic_stats(short_url_id)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        country,
        city,
        count() as clicks,
        uniq(ip_address) as unique_visitors
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
        AND country != ''
      GROUP BY country, city
      ORDER BY clicks DESC
      LIMIT 50
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse geographic_stats failed: #{e.message}")
    []
  end

  # Get device type statistics
  def self.device_stats(short_url_id)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        device_type,
        count() as clicks,
        uniq(ip_address) as unique_visitors
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
      GROUP BY device_type
      ORDER BY clicks DESC
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse device_stats failed: #{e.message}")
    []
  end

  # Get browser statistics
  def self.browser_stats(short_url_id)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        browser,
        browser_version,
        count() as clicks
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
        AND browser != ''
      GROUP BY browser, browser_version
      ORDER BY clicks DESC
      LIMIT 20
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse browser_stats failed: #{e.message}")
    []
  end

  # Get referrer statistics
  def self.referrer_stats(short_url_id)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        referrer_domain,
        count() as clicks,
        uniq(ip_address) as unique_visitors
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
        AND referrer_domain != ''
      GROUP BY referrer_domain
      ORDER BY clicks DESC
      LIMIT 20
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse referrer_stats failed: #{e.message}")
    []
  end

  # Get hourly click pattern
  def self.hourly_pattern(short_url_id, days: 7)
    config = get_clickhouse_config
    return [] unless config

    query = <<~SQL
      SELECT#{' '}
        toHour(clicked_at) as hour,
        count() as clicks
      FROM url_clicks
      WHERE short_url_id = #{short_url_id}
        AND clicked_at >= today() - #{days}
      GROUP BY hour
      ORDER BY hour
      FORMAT JSONEachRow
    SQL

    result = execute_raw(config, query)
    parse_json_result(result)
  rescue => e
    Rails.logger.error("ClickHouse hourly_pattern failed: #{e.message}")
    []
  end

  # Get comprehensive stats for a short URL
  def self.comprehensive_stats(short_url_id, days: 30)
    {
      total_clicks: total_clicks(short_url_id),
      url_type_breakdown: clicks_by_url_type(short_url_id),
      clicks_over_time: clicks_over_time(short_url_id, days: days),
      geographic_stats: geographic_stats(short_url_id),
      device_stats: device_stats(short_url_id),
      browser_stats: browser_stats(short_url_id),
      referrer_stats: referrer_stats(short_url_id),
      hourly_pattern: hourly_pattern(short_url_id, days: days)
    }
  end

  # Get recent clicks for a short URL
  def self.recent_clicks(short_url_id, limit: 100)
    where("short_url_id = ?", short_url_id)
      .order("clicked_at DESC")
      .limit(limit)
  end

  private

  def self.generate_unique_id
    Time.now.to_i * 1000 + rand(1000)
  end

  def self.get_clickhouse_config
    # Read directly from database.yml
    db_config = Rails.application.config.database_configuration
    env_config = db_config[Rails.env]

    unless env_config && env_config["clickhouse"]
      Rails.logger.error("ClickHouse configuration not found in database.yml for #{Rails.env} environment")
      return nil
    end

    clickhouse_config = env_config["clickhouse"]

    # Return configuration hash
    {
      host: clickhouse_config["host"],
      port: clickhouse_config["port"] || 8443,
      database: clickhouse_config["database"],
      username: clickhouse_config["username"],
      password: clickhouse_config["password"]
    }
  rescue => e
    Rails.logger.error("Failed to load ClickHouse config: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  def self.execute_raw(config, query)
    return "" unless config

    uri = URI.parse("https://#{config[:host]}:#{config[:port]}/")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(uri.request_uri)
    request.basic_auth(config[:username], config[:password])
    request.body = query
    request["Content-Type"] = "text/plain"

    response = http.request(request)

    unless response.code.to_i == 200
      raise "ClickHouse query failed: #{response.body}"
    end

    response.body
  end

  def self.parse_json_result(result)
    return [] if result.strip.empty?
    result.strip.split("\n").map { |line| JSON.parse(line) }
  end

  def self.escape_string(str)
    str.to_s.gsub("'", "''").gsub("\\", "\\\\\\\\")
  end

  # Parse user agent string
  def self.parse_user_agent(user_agent)
    browser = "Unknown"
    version = ""
    os = "Unknown"
    os_version = ""
    device_type = "desktop"

    ua = user_agent.downcase

    # Detect browser
    if ua.include?("chrome") && !ua.include?("edg")
      browser = "Chrome"
      version = ua[/chrome\/([\d.]+)/, 1] || ""
    elsif ua.include?("safari") && !ua.include?("chrome")
      browser = "Safari"
      version = ua[/version\/([\d.]+)/, 1] || ""
    elsif ua.include?("firefox")
      browser = "Firefox"
      version = ua[/firefox\/([\d.]+)/, 1] || ""
    elsif ua.include?("edg")
      browser = "Edge"
      version = ua[/edg\/([\d.]+)/, 1] || ""
    end

    # Detect OS
    if ua.include?("windows")
      os = "Windows"
      os_version = ua[/windows nt ([\d.]+)/, 1] || ""
    elsif ua.include?("mac os x")
      os = "macOS"
      os_version = ua[/mac os x ([\d_]+)/, 1]&.gsub("_", ".") || ""
    elsif ua.include?("android")
      os = "Android"
      os_version = ua[/android ([\d.]+)/, 1] || ""
    elsif ua.include?("iphone") || ua.include?("ipad")
      os = "iOS"
      os_version = ua[/os ([\d_]+)/, 1]&.gsub("_", ".") || ""
    elsif ua.include?("linux")
      os = "Linux"
    end

    # Detect device type
    if ua.include?("mobile") || ua.include?("android") || ua.include?("iphone")
      device_type = "mobile"
    elsif ua.include?("tablet") || ua.include?("ipad")
      device_type = "tablet"
    end

    {
      browser: browser,
      version: version,
      os: os,
      os_version: os_version,
      device_type: device_type
    }
  end

  # Get location info from IP (placeholder - integrate with IP geolocation service)
  def self.get_location_info(ip_address)
    {
      country: "",
      city: "",
      region: ""
    }
  end
end
