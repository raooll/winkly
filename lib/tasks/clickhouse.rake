# lib/tasks/clickhouse.rake

namespace :clickhouse do
  namespace :db do
    desc "Create ClickHouse database"
    task create: :environment do
      config = get_clickhouse_config
      puts "Creating ClickHouse database: #{config[:database]}"

      # Connect without database to create it
      create_config = config.merge(database: "default")
      execute_query(create_config, "CREATE DATABASE IF NOT EXISTS #{config[:database]}")
      puts "✅ Database created successfully!"
    rescue => e
      puts "❌ Error creating database: #{e.message}"
      puts e.backtrace.first(5)
    end

    desc "Drop ClickHouse database"
    task drop: :environment do
      config = get_clickhouse_config
      puts "Dropping ClickHouse database: #{config[:database]}"

      execute_query(config, "DROP DATABASE IF EXISTS #{config[:database]}")
      puts "✅ Database dropped successfully!"
    rescue => e
      puts "❌ Error dropping database: #{e.message}"
    end

    desc "Check ClickHouse database status"
    task status: :environment do
      config = get_clickhouse_config
      puts "ClickHouse Configuration:"
      puts "  Host: #{config[:host]}"
      puts "  Port: #{config[:port]}"
      puts "  Database: #{config[:database]}"
      puts "  Username: #{config[:username]}"
      puts ""

      # Test connection
      result = execute_query(config, "SELECT version()")
      puts "✅ Connection successful!"
      puts "ClickHouse Version: #{result.strip}"

      # Show tables
      tables = execute_query(config, "SHOW TABLES")
      puts "\nTables in database:"
      if tables.strip.empty?
        puts "  (no tables)"
      else
        tables.strip.split("\n").each do |table|
          puts "  - #{table}"
        end
      end
    rescue => e
      puts "❌ Connection failed: #{e.message}"
      puts e.backtrace.first(5)
    end

    desc "Run ClickHouse migrations"
    task migrate: :environment do
      config = get_clickhouse_config
      migration_dir = Rails.root.join("db", "clickhouse_migrate")

      unless Dir.exist?(migration_dir)
        puts "❌ Migration directory not found: #{migration_dir}"
        exit 1
      end

      # Get all migration files
      migration_files = Dir.glob(migration_dir.join("*.rb")).sort

      if migration_files.empty?
        puts "No migrations found"
        exit 0
      end

      puts "Running ClickHouse migrations..."
      migration_files.each do |file|
        puts "\nRunning: #{File.basename(file)}"
        load file

        # Get the migration class
        migration_class = File.basename(file, ".rb").split("_")[1..-1].join("_").camelize.constantize
        migration = migration_class.new

        # Run the up method
        migration.up
        puts "✅ Completed: #{File.basename(file)}"
      end

      puts "\n✅ All migrations completed!"
    rescue => e
      puts "❌ Migration failed: #{e.message}"
      puts e.backtrace.first(10)
    end

    desc "Rollback ClickHouse migrations"
    task rollback: :environment do
      config = get_clickhouse_config
      migration_dir = Rails.root.join("db", "clickhouse_migrate")

      # Get all migration files
      migration_files = Dir.glob(migration_dir.join("*.rb")).sort.reverse

      if migration_files.empty?
        puts "No migrations found"
        exit 0
      end

      puts "Rolling back ClickHouse migrations..."
      migration_file = migration_files.first

      puts "\nRolling back: #{File.basename(migration_file)}"
      load migration_file

      # Get the migration class
      migration_class = File.basename(migration_file, ".rb").split("_")[1..-1].join("_").camelize.constantize
      migration = migration_class.new

      # Run the down method
      migration.down
      puts "✅ Rollback completed!"
    rescue => e
      puts "❌ Rollback failed: #{e.message}"
      puts e.backtrace.first(10)
    end
  end

  private

  def get_clickhouse_config
    # Read directly from database.yml
    db_config = Rails.application.config.database_configuration
    env_config = db_config[Rails.env]

    unless env_config && env_config["clickhouse"]
      raise "ClickHouse configuration not found in database.yml for #{Rails.env} environment"
    end

    clickhouse_config = env_config["clickhouse"]

    {
      host: clickhouse_config["host"],
      port: clickhouse_config["port"] || 8443,
      database: clickhouse_config["database"],
      username: clickhouse_config["username"],
      password: clickhouse_config["password"],
      ssl: clickhouse_config["ssl"] != false
    }
  end

  def execute_query(config, query)
    require "net/http"
    require "uri"

    uri = URI.parse("https://#{config[:host]}:#{config[:port]}/")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request.basic_auth(config[:username], config[:password])
    request.body = "USE #{config[:database]}; #{query}"
    request["Content-Type"] = "text/plain"

    response = http.request(request)

    unless response.code.to_i == 200
      raise "ClickHouse query failed (#{response.code}): #{response.body}"
    end

    response.body
  end
end
