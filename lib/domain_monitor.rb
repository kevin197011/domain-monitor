# frozen_string_literal: true

require 'domain_monitor/version'
require 'domain_monitor/config'
require 'domain_monitor/nacos_client'
require 'domain_monitor/whois_client'
require 'domain_monitor/checker'
require 'domain_monitor/exporter'

module DomainMonitor
  class Error < StandardError; end

  class Application
    SHUTDOWN_TIMEOUT = 5 # 关闭超时时间（秒）

    def initialize
      @config = Config.instance
      @checker = Checker.new(@config)
      @nacos_client = NacosClient.new(@config)
      @server_thread = nil
      @shutdown_requested = false
      @force_shutdown = false
    end

    def start
      # 设置信号处理
      setup_signal_handlers

      # Start the domain checker
      @checker.start

      # Start Nacos config listener
      @nacos_client.start_listening do |config_content|
        @config.update_domains_config(config_content) if config_content
      end

      # Start the metrics server in a separate thread
      @server_thread = Exporter.run_server!(@checker, @config)

      # 主循环
      sleep 1 until @shutdown_requested

      # 执行清理
      perform_cleanup
    end

    private

    def setup_signal_handlers
      # 第一次 Ctrl+C：优雅关闭
      Signal.trap('INT') do
        if @shutdown_requested
          # 第二次 Ctrl+C：强制关闭
          @force_shutdown = true
        else
          @shutdown_requested = true
        end
      end

      # SIGTERM 处理
      Signal.trap('TERM') do
        @shutdown_requested = true
      end
    end

    def perform_cleanup
      puts "\nShutting down gracefully..."
      shutdown_start = Time.now

      cleanup_thread = Thread.new do
        # 停止检查器
        begin
          @checker.stop
        rescue StandardError => e
          puts "Error stopping checker: #{e.message}"
        end

        # 停止 Nacos 客户端
        begin
          @nacos_client.stop
        rescue StandardError => e
          puts "Error stopping Nacos client: #{e.message}"
        end

        # 停止 WEBrick 服务器
        if @server_thread&.alive?
          begin
            puts 'Stopping metrics server...'
            ObjectSpace.each_object(WEBrick::HTTPServer, &:shutdown)
            @server_thread.join(2)
          rescue StandardError => e
            puts "Error stopping server: #{e.message}"
          end
        end
      end

      # 等待清理完成或超时/强制关闭
      while cleanup_thread.alive?
        if @force_shutdown || (Time.now - shutdown_start) > SHUTDOWN_TIMEOUT
          puts "\nForce shutdown initiated..."
          cleanup_thread.kill
          break
        end
        sleep 0.1
      end

      puts 'Shutdown complete'
      exit!(0)
    end
  end
end
