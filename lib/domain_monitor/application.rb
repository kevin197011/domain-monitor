# frozen_string_literal: true

module DomainMonitor
  class Application
    SHUTDOWN_TIMEOUT = 5 # Shutdown timeout in seconds

    def initialize
      @config = Config.instance
      @checker = Checker.new(@config)
      @nacos_client = NacosClient.new(@config)
      @server_thread = nil
      @shutdown_requested = false
      @force_shutdown = false
    end

    def start
      # Setup signal handlers
      setup_signal_handlers

      # Start the domain checker
      @checker.start

      # Start Nacos config listener
      @nacos_client.start_listening do |config_content|
        @config.update_domains_config(config_content) if config_content
      end

      # Start the metrics server in a separate thread
      @server_thread = Exporter.run_server!(@checker, @config)

      # Main loop
      sleep 1 until @shutdown_requested

      # Perform cleanup
      perform_cleanup
    end

    private

    def setup_signal_handlers
      # First Ctrl+C: graceful shutdown
      Signal.trap('INT') do
        if @shutdown_requested
          # Second Ctrl+C: force shutdown
          @force_shutdown = true
        else
          @shutdown_requested = true
        end
      end

      # SIGTERM handler
      Signal.trap('TERM') do
        @shutdown_requested = true
      end
    end

    def perform_cleanup
      puts "\nShutting down gracefully..."
      shutdown_start = Time.now

      cleanup_thread = Thread.new do
        # Stop checker
        begin
          @checker.stop
        rescue StandardError => e
          puts "Error stopping checker: #{e.message}"
        end

        # Stop Nacos client
        begin
          @nacos_client.stop
        rescue StandardError => e
          puts "Error stopping Nacos client: #{e.message}"
        end

        # Stop Puma server
        if @server_thread&.alive?
          begin
            puts 'Stopping metrics server...'
            Process.kill('SIGTERM', Process.pid)
            @server_thread.join(2)
          rescue StandardError => e
            puts "Error stopping server: #{e.message}"
          end
        end
      end

      # Wait for cleanup to complete or timeout/force shutdown
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
