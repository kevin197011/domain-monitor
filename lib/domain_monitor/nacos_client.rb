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
      @polling_interval = 30 # 轮询间隔（秒）
      @running = false

      # 解析 Nacos 服务器地址
      @uri = URI.parse(@config.nacos_addr)
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https'
    end

    def start_listening(&callback)
      @logger.info 'Starting Nacos config listener...'
      @running = true

      # Initial config load
      current_config = fetch_config
      callback.call(current_config) if current_config && callback

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
              @logger.info 'Received config update from Nacos'
              callback&.call(new_config)
              last_md5 = new_md5
            end
          rescue StandardError => e
            @logger.error "Error in Nacos polling: #{e.message}"
            @logger.error e.backtrace.join("\n")
          end
        end
      end
    rescue StandardError => e
      @logger.error "Error in Nacos client: #{e.message}"
      @logger.error e.backtrace.join("\n")
      raise
    end

    def stop
      @running = false
      @polling_thread&.join
    end

    private

    def fetch_config
      # 构建请求参数
      params = {
        tenant: @config.nacos_namespace,
        dataId: @config.nacos_data_id,
        group: @config.nacos_group
      }

      # 构建请求路径
      path = "/nacos/v1/cs/configs?#{URI.encode_www_form(params)}"

      # 发送请求
      request = Net::HTTP::Get.new(path)
      request['Content-Type'] = 'application/x-www-form-urlencoded'

      response = @http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      else
        @logger.error "Failed to fetch config from Nacos: #{response.code} - #{response.body}"
        nil
      end
    rescue StandardError => e
      @logger.error "Failed to fetch config from Nacos: #{e.message}"
      nil
    end

    def calculate_md5(content)
      require 'digest/md5'
      Digest::MD5.hexdigest(content.to_s)
    end
  end
end
