# db/clickhouse_migrate/002_add_utm_parameters_to_url_clicks.rb

class AddUtmParametersToUrlClicks
  def up
    # Add UTM tracking columns
    execute <<-SQL
      ALTER TABLE url_clicks#{' '}
      ADD COLUMN utm_source Nullable(String)
    SQL

    execute <<-SQL
      ALTER TABLE url_clicks#{' '}
      ADD COLUMN utm_medium Nullable(String)
    SQL

    execute <<-SQL
      ALTER TABLE url_clicks#{' '}
      ADD COLUMN utm_campaign Nullable(String)
    SQL

    execute <<-SQL
      ALTER TABLE url_clicks#{' '}
      ADD COLUMN utm_term Nullable(String)
    SQL

    execute <<-SQL
      ALTER TABLE url_clicks#{' '}
      ADD COLUMN utm_content Nullable(String)
    SQL

    puts "✅ UTM parameters columns added to url_clicks table"
  end

  def down
    execute "ALTER TABLE url_clicks DROP COLUMN utm_source"
    execute "ALTER TABLE url_clicks DROP COLUMN utm_medium"
    execute "ALTER TABLE url_clicks DROP COLUMN utm_campaign"
    execute "ALTER TABLE url_clicks DROP COLUMN utm_term"
    execute "ALTER TABLE url_clicks DROP COLUMN utm_content"

    puts "✅ UTM parameters columns removed from url_clicks table"
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
