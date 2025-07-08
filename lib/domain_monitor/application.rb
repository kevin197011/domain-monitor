# frozen_string_literal: true

module DomainMonitor
  # Main application class that handles initialization and startup
  class Application
    attr_reader :logger, :nacos_client, :checker

    def initialize
      @logger = Logger.create('System')
      @logger.level = ::Logger::INFO # 初始设置为 INFO，后续从配置更新
      @config_change_trigger = Concurrent::Event.new
      @shutdown = false
      @checker_task = nil
    end

    def start
      setup_configuration
      start_nacos_client if Config.nacos_enabled?
      setup_logger
      setup_components
      trap_signals
      start_exporter
      start_checker_task
      wait_for_shutdown
    rescue StandardError => e
      logger.error "Startup failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      exit 1
    end

    # Nacos配置变化时的回调方法
    def on_config_changed
      logger.info 'Nacos configuration changed, triggering immediate domain check...'
      @config_change_trigger.set
    end

    # 捕获 SIGINT/SIGTERM 信号，优雅退出
    def trap_signals
      %w[INT TERM].each do |sig|
        Signal.trap(sig) do
          logger.info "Received signal #{sig}, shutting down gracefully..."
          @shutdown = true
        end
      end
    end

    # 等待关闭信号并 join checker 线程
    def wait_for_shutdown
      sleep 0.5 until @shutdown
      logger.info 'Shutting down checker task...'
      @checker_task&.shutdown
      @event_thread&.kill
      logger.info 'Shutdown complete.'
    end

    private

    def setup_configuration
      logger.debug 'Loading configuration...'
      Config.load
      logger.debug "Configuration loaded: #{Config.inspect}"
    end

    def wait_for_initial_config
      logger.info 'Waiting for initial configuration from Nacos...'
      max_wait = 30 # 最多等待30秒
      start_time = Time.now

      sleep 1 while Config.domains.empty? && (Time.now - start_time) < max_wait

      if Config.domains.empty?
        logger.warn 'No domains loaded from Nacos after 30 seconds, continuing with empty domain list'
      else
        logger.info "Successfully loaded #{Config.domains.size} domains from Nacos"
      end
    end

    def setup_logger
      logger.debug 'Setting up logger...'
      # 从配置中读取日志级别
      log_level = (Config.log_level || 'info').upcase
      Logger.update_all_level(::Logger.const_get(log_level))

      # 输出当前配置
      logger.info 'Current configuration:'
      logger.info "- Domains: #{Config.domains.join(', ')}"
      logger.info "- Check interval: #{Config.check_interval}s"
      logger.info "- Expire threshold days: #{Config.expire_threshold_days}"
      logger.info "- Max concurrent checks: #{Config.max_concurrent_checks}"
      logger.info "- Metrics port: #{Config.metrics_port}"
      logger.info "- Log level: #{Config.log_level}"
      logger.info "- Nacos enabled: #{Config.nacos_enabled?}"
    end

    def setup_components
      logger.debug 'Initializing components...'
      @checker = Checker.new(Config)
      logger.debug 'Components initialized'
    end

    def start_nacos_client
      logger.info 'Starting Nacos config listener...'
      @nacos_client = NacosClient.new
      # 设置配置变化回调
      @nacos_client.on_config_change_callback = method(:on_config_changed)
      @nacos_client.start_listening
    end

    def start_checker_task
      @checker_task = Concurrent::TimerTask.new(execution_interval: Config.check_interval, timeout_interval: 60) do
        run_domain_check
      end
      @checker_task.execute

      # 监听配置变更事件，立即触发检查
      @event_thread = Thread.new do
        loop do
          @config_change_trigger.wait
          break if @shutdown

          @config_change_trigger.reset
          run_domain_check
        end
      end
    end

    def run_domain_check
      domains = Config.domains
      if domains.empty?
        logger.warn 'No domains configured, skipping check.'
        return
      end
      begin
        @checker.update_domain_list(domains)
        @checker.check_all_domains(Config)
        Exporter.update_metrics(@checker)
        logger.info "Checked #{domains.size} domains."
      rescue StandardError => e
        logger.error "Domain check failed: #{e.message}"
      end
    end

    def start_exporter
      logger.debug 'Starting metrics exporter...'
      # 设置 Sinatra 服务器选项
      Exporter.set :port, Config.metrics_port
      Exporter.run! host: '0.0.0.0'
    end
  end
end
