# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'logger'

module DomainMonitor
  class NacosClient
    def initialize(config = Config.instance)
      @config = config
      @logger = config.create_logger('Nacos')
      @polling_interval = 30 # Polling interval in seconds
      @running = false

      # Parse Nacos server address
      @uri = URI.parse(@config.nacos_addr)
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https'
    end

    def start_listening(&callback)
      @logger.info 'Starting Nacos config listener'
      @running = true

      # Initial config load
      current_config = fetch_config
      if current_config
        @logger.info 'Initial config loaded from Nacos'
        callback&.call(current_config)
      else
        @logger.warn 'Failed to load initial config from Nacos'
      end

      # Start polling in a separate thread
      @polling_thread = Thread.new do
        last_md5 = calculate_md5(current_config)

        while @running
          begin
            sleep @polling_interval
            new_config = fetch_config
            next unless new_config

            new_md5 = calculate_md5(new_config)
            if new_md5 != last_md5
              @logger.info 'Config update detected in Nacos'
              callback&.call(new_config)
              last_md5 = new_md5
            else
              @logger.debug 'No config changes detected'
            end
          rescue StandardError => e
            @logger.error "Nacos polling error: #{e.message}"
            @logger.debug e.backtrace.join("\n")
          end
        end
      end
    rescue StandardError => e
      @logger.error "Failed to start Nacos client: #{e.message}"
      @logger.debug e.backtrace.join("\n")
      raise
    end

    def stop
      @logger.info 'Stopping Nacos config listener'
      @running = false
      @polling_thread&.join
      @logger.info 'Nacos config listener stopped'
    end

    private

    def fetch_config
      # Build request parameters
      params = {
        tenant: @config.nacos_namespace,
        dataId: @config.nacos_data_id,
        group: @config.nacos_group
      }

      # Build request path
      path = "/nacos/v1/cs/configs?#{URI.encode_www_form(params)}"

      # Send request
      request = Net::HTTP::Get.new(path)
      request['Content-Type'] = 'application/x-www-form-urlencoded'

      @logger.debug "Fetching config from Nacos: #{path}"
      response = @http.request(request)

      case response
      when Net::HTTPSuccess
        @logger.debug 'Successfully fetched config from Nacos'
        response.body
      else
        @logger.error "Failed to fetch config from Nacos: #{response.code} - #{response.body}"
        nil
      end
    rescue StandardError => e
      @logger.error "Failed to fetch config from Nacos: #{e.message}"
      @logger.debug e.backtrace.join("\n")
      nil
    end

    def calculate_md5(content)
      require 'digest/md5'
      Digest::MD5.hexdigest(content.to_s)
    end
  end
end
