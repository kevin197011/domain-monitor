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
      @access_token = nil
      @token_expires_at = nil

      # Parse Nacos server address
      @uri = URI.parse(@config.nacos_addr)
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https'

      # Authenticate if username and password are provided
      authenticate if authentication_required?
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

    def authentication_required?
      !@config.nacos_username.nil? && !@config.nacos_username.empty? &&
        !@config.nacos_password.nil? && !@config.nacos_password.empty?
    end

    def authenticate
      @logger.info 'Authenticating with Nacos server'

      # Build authentication request
      auth_path = '/nacos/v1/auth/login'
      params = {
        username: @config.nacos_username,
        password: @config.nacos_password
      }

      request = Net::HTTP::Post.new(auth_path)
      request.set_form_data(params)
      request['Content-Type'] = 'application/x-www-form-urlencoded'

      response = @http.request(request)

      case response
      when Net::HTTPSuccess
        auth_data = JSON.parse(response.body)
        @access_token = auth_data['accessToken']
        @token_expires_at = Time.now + (auth_data['tokenTtl'] || 18_000) # Default 5 hours
        @logger.info 'Successfully authenticated with Nacos'
        @logger.debug "Access token expires at: #{@token_expires_at}"
      else
        @logger.error "Failed to authenticate with Nacos: #{response.code} - #{response.body}"
        raise "Nacos authentication failed: #{response.code}"
      end
    rescue JSON::ParserError => e
      @logger.error "Failed to parse authentication response: #{e.message}"
      raise "Nacos authentication response parsing failed: #{e.message}"
    rescue StandardError => e
      @logger.error "Authentication error: #{e.message}"
      @logger.debug e.backtrace.join("\n")
      raise
    end

    def ensure_authentication
      return unless authentication_required?

      # Check if token is expired or will expire soon (5 minutes buffer)
      if @access_token.nil? || @token_expires_at.nil? ||
         Time.now >= (@token_expires_at - 300)
        @logger.info 'Access token expired or expiring soon, re-authenticating'
        authenticate
      end
    end

    def add_auth_header(request)
      return unless authentication_required? && @access_token

      request['Authorization'] = "Bearer #{@access_token}"
    end

    def fetch_config
      # Ensure authentication is valid
      ensure_authentication

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

      # Add authentication header if required
      add_auth_header(request)

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
