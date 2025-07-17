# frozen_string_literal: true

module DomainMonitor
  # Configuration management class for domain-monitor
  # Handles loading and validating configuration from Nacos or local file
  class Config
    class << self
      attr_accessor :nacos_addr, :nacos_namespace, :nacos_group, :nacos_data_id,
                    :nacos_username, :nacos_password,
                    :domains, :whois_retry_times, :whois_retry_interval,
                    :check_interval, :expire_threshold_days, :max_concurrent_checks,
                    :metrics_port, :log_level, :nacos_poll_interval

      def load
        # Set default values
        set_defaults

        # Load .env file for Nacos connection info only
        Dotenv.load

        # Load essential Nacos connection info from environment
        load_nacos_connection_config

        # Load configuration from Nacos or local file
        if nacos_enabled?
          # Validate Nacos configuration
          validate_nacos_config
          logger.info 'Nacos configuration enabled, waiting for remote config...'
        else
          # Load from local configuration file
          load_local_config
          logger.info 'Using local configuration file'
        end
      end

      def nacos_enabled?
        !@nacos_addr.nil? && !@nacos_addr.empty?
      end

      def update_app_config(config_data)
        return false unless config_data.is_a?(Hash)

        # Update domains configuration
        @domains = Array(config_data['domains'] || [])

        # Update settings configuration
        settings = config_data['settings'] || {}

        # Update application configuration from settings
        @whois_retry_times = (settings['whois_retry_times'] || @whois_retry_times).to_i
        @whois_retry_interval = (settings['whois_retry_interval'] || @whois_retry_interval).to_i
        @check_interval = (settings['check_interval'] || @check_interval).to_i
        @expire_threshold_days = (settings['expire_threshold_days'] || @expire_threshold_days).to_i
        @max_concurrent_checks = (settings['max_concurrent_checks'] || @max_concurrent_checks).to_i
        @metrics_port = (settings['metrics_port'] || @metrics_port).to_i
        @log_level = (settings['log_level'] || @log_level).to_s.downcase
        @nacos_poll_interval = (settings['nacos_poll_interval'] || @nacos_poll_interval).to_i

        # Validate configuration
        validate_app_config
        # 新增 info 日志
        logger.info "App config updated: domains=#{@domains.size}, check_interval=#{@check_interval}, max_concurrent=#{@max_concurrent_checks}, expire_threshold_days=#{@expire_threshold_days}, metrics_port=#{@metrics_port}"
        true
      rescue StandardError => e
        logger.error "Configuration update error: #{e.message}"
        false
      end

      private

      def set_defaults
        @log_level = 'info'
        @metrics_port = 9394
        @check_interval = 3600 # Default to 3600 seconds for domain check interval
        @whois_retry_times = 3
        @whois_retry_interval = 5
        @expire_threshold_days = 15
        @domains = []
        @nacos_poll_interval = 60 # Default to 60 seconds for Nacos polling
        @max_concurrent_checks = 50 # Default to 50 concurrent checks
      end

      def load_nacos_connection_config
        # Load Nacos connection info from environment
        @nacos_addr = ENV['NACOS_ADDR']
        @nacos_namespace = ENV['NACOS_NAMESPACE']
        @nacos_group = ENV['NACOS_GROUP'] || 'DEFAULT_GROUP'
        @nacos_data_id = ENV['NACOS_DATA_ID'] || 'domain-monitor-config'
        @nacos_username = ENV['NACOS_USERNAME']
        @nacos_password = ENV['NACOS_PASSWORD']
      end

      def load_local_config
        config_file = ENV['CONFIG_FILE'] || 'config/domains.yml'

        unless File.exist?(config_file)
          logger.warn "Configuration file #{config_file} not found, using defaults"
          return
        end

        begin
          config_data = YAML.load_file(config_file)
          logger.debug "Loaded configuration from #{config_file}: #{config_data.inspect}"

          if config_data.is_a?(Hash)
            update_app_config(config_data)
            logger.info "Configuration loaded successfully from #{config_file}"
          else
            logger.error "Invalid configuration format in #{config_file}"
          end
        rescue StandardError => e
          logger.error "Failed to load configuration from #{config_file}: #{e.message}"
          logger.debug e.backtrace.join("\n")
        end
      end

      def validate_nacos_config
        raise 'NACOS_ADDR is required' if @nacos_addr.nil? || @nacos_addr.empty?
        # nacos_namespace can be empty (for default namespace)
        raise 'NACOS_GROUP is required' if @nacos_group.nil? || @nacos_group.empty?
        raise 'NACOS_DATA_ID is required' if @nacos_data_id.nil? || @nacos_data_id.empty?

        # username and password are optional but should be used together
        return unless @nacos_username && @nacos_password

        logger.info 'Nacos authentication enabled'
      end

      def validate_app_config
        # Validate log level
        @log_level = 'info' unless %w[debug info warn error fatal].include?(@log_level)

        # Allow empty domain list for initial setup
        if @domains.empty?
          logger.warn 'Domain list is empty'
          return
        end

        # Validate domain list
        raise 'Domain list must be an array' unless @domains.is_a?(Array)

        # Validate each domain format
        @domains.each do |domain|
          raise "Invalid domain format: #{domain}" unless domain.is_a?(String) && !domain.empty?
        end

        # Validate numeric values
        raise 'Metrics port must be between 1 and 65535' unless (1..65_535).include?(@metrics_port)
        raise 'Check interval must be positive' unless @check_interval.positive?
        raise 'WHOIS retry times must be positive' unless @whois_retry_times.positive?
        raise 'WHOIS retry interval must be positive' unless @whois_retry_interval.positive?
        raise 'Expire threshold days must be positive' unless @expire_threshold_days.positive?
        raise 'Nacos poll interval must be positive' unless @nacos_poll_interval.positive?
        raise 'Max concurrent checks must be positive' unless @max_concurrent_checks.positive?
      end

      def logger
        @logger ||= Logger.create('Config')
      end
    end
  end
end
