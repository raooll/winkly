# db/clickhouse_migrate/001_create_url_clicks.rb

class CreateUrlClicks
  def up
    execute <<-SQL
      CREATE TABLE IF NOT EXISTS url_clicks (
          id UInt64,
          short_url_id UInt64,
          tracking_id String,
          short_uri String,
          redirected_to_url String,
          url_type String,
      #{'    '}
          user_id Nullable(UInt64),
          session_id Nullable(String),
      #{'    '}
          user_agent Nullable(String),
          browser Nullable(String),
          browser_version Nullable(String),
          device_type Nullable(String),
          os Nullable(String),
          os_version Nullable(String),
      #{'    '}
          ip_address Nullable(String),
          country Nullable(String),
          city Nullable(String),
          region Nullable(String),
      #{'    '}
          referrer Nullable(String),
          referrer_domain Nullable(String),
      #{'    '}
          clicked_at DateTime,
          created_at DateTime DEFAULT now(),
      #{'    '}
          properties String DEFAULT '{}'
      )
      ENGINE = MergeTree()
      PARTITION BY toYYYYMM(clicked_at)
      ORDER BY (short_url_id, clicked_at, id)
      SETTINGS index_granularity = 8192
    SQL
    puts "✅ url_clicks table created"
  end

  def down
    execute "DROP TABLE IF EXISTS url_clicks"
    puts "✅ url_clicks table dropped"
  end

  private

  def execute(query)
    config = get_clickhouse_config
    execute_query(config, query)
  end

  def get_clickhouse_config
    db_config = Rails.application.config.database_configuration
    env_config = db_config[Rails.env]
    clickhouse_config = env_config["clickhouse"]

    {
      host: clickhouse_config["host"],
      port: clickhouse_config["port"] || 8443,
      database: clickhouse_config["database"],
      username: clickhouse_config["username"],
      password: clickhouse_config["password"]
    }
  end

  def execute_query(config, query)
    require "net/http"
    require "uri"

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
end
