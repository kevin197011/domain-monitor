# frozen_string_literal: true

module DomainMonitor
  # Main application class that handles initialization and startup
  class Application
    attr_reader :logger, :nacos_client, :checker

    def initialize
      @logger = Logger.create('System')
      @logger.level = ::Logger::INFO # 初始设置为 INFO，后续从配置更新
      @checker_thread = nil
      @config_change_trigger = Concurrent::Event.new
    end

    def start
      logger.debug 'Starting application...'
      setup_configuration

      if Config.nacos_enabled?
        logger.info 'Nacos configuration enabled, waiting for remote config...'
        start_nacos_client
        # 等待首次配置加载
        wait_for_initial_config
      end

      setup_logger
      setup_components

      # 初次阻塞域名检查 - 确保应用启动时有完整的域名状态
      perform_initial_domain_check

      # 启动异步检查线程 - 基于Nacos配置的定时检测
      start_async_checker

      # 启动指标服务器
      start_exporter
    rescue StandardError => e
      logger.error "Startup failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      exit 1
    end

    # Nacos配置变化时的回调方法
    def on_config_changed
      logger.info 'Nacos configuration changed, triggering immediate domain check...'
      logger.debug 'Setting config_change_trigger event.'
      @config_change_trigger.set
      logger.debug 'config_change_trigger event set.'
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

    def perform_initial_domain_check
      if Config.domains.empty?
        logger.warn 'No domains configured, skipping initial domain check'
        return
      end

      # 获取当前Nacos配置
      initial_domains = Config.domains
      initial_concurrent = Config.max_concurrent_checks
      initial_threshold = Config.expire_threshold_days

      logger.info '=== Performing initial domain check (blocking) ==='
      logger.info "Checking #{initial_domains.length} domains synchronously (concurrency: #{initial_concurrent})..."

      start_time = Time.now

      # 使用当前Nacos配置执行初次域名检查
      @checker.check_all_domains(Config)

      # 更新指标
      Exporter.update_metrics(@checker)
      successful_checks = @checker.domain_metrics.count { |_, m| !m[:error] }
      elapsed_time = (Time.now - start_time).round(2)

      logger.info "Initial domain check completed in #{elapsed_time}s: #{successful_checks}/#{initial_domains.length} successful"

      # 输出每个域名的检查结果
      @checker.domain_metrics.each do |domain, metrics|
        if metrics[:error]
          logger.warn "  - #{domain}: FAILED (#{metrics[:error]})"
        else
          status = metrics[:days_until_expiry] <= initial_threshold ? 'CRITICAL' : 'OK'
          logger.info "  - #{domain}: #{metrics[:days_until_expiry]} days (#{status})"
        end
      end

      logger.info '=== Initial domain check completed, starting async monitoring ==='
    end

    def start_async_checker
      logger.info 'Starting asynchronous domain checker thread...'
      logger.info "Will check domains every #{Config.check_interval} seconds based on Nacos configuration"

      @checker_thread = Thread.new do
        logger.debug '[AsyncChecker] Thread started.'
        begin
          # 等待第一个检测周期
          logger.debug "[AsyncChecker] Sleeping for initial interval: #{Config.check_interval}s"
          sleep Config.check_interval

          loop do
            logger.debug '[AsyncChecker] Waiting for config_change_trigger or interval timeout...'
            if @config_change_trigger.wait(Config.check_interval)
              logger.info '=== Config change triggered domain check ==='
              logger.debug '[AsyncChecker] config_change_trigger event detected, resetting event.'
              @config_change_trigger.reset
            else
              logger.info '=== Scheduled domain check ==='
              logger.debug '[AsyncChecker] Interval timeout, scheduled check.'
            end

            # 重新读取当前Nacos配置
            current_domains = Config.domains
            current_interval = Config.check_interval
            current_concurrent = Config.max_concurrent_checks

            logger.debug '[AsyncChecker] Current domains: ', current_domains.inspect
            logger.debug "[AsyncChecker] Current interval: #{current_interval}, concurrency: #{current_concurrent}"

            if current_domains.empty?
              logger.debug '[AsyncChecker] No domains configured, skipping check.'
            else
              logger.info "Checking #{current_domains.length} domains (interval: #{current_interval}s, concurrency: #{current_concurrent})"
              begin
                start_time = Time.now
                logger.debug '[AsyncChecker] Updating domain list in checker.'
                @checker.update_domain_list(current_domains)
                logger.debug '[AsyncChecker] Domain list updated.'
                logger.debug '[AsyncChecker] Starting check_all_domains.'
                @checker.check_all_domains(Config)
                logger.debug '[AsyncChecker] check_all_domains finished.'
                Exporter.update_metrics(@checker)
                logger.debug '[AsyncChecker] Metrics updated.'
                successful_checks = @checker.domain_metrics.count { |_, m| !m[:error] }
                elapsed_time = (Time.now - start_time).round(2)
                logger.info "Domain check completed in #{elapsed_time}s: #{successful_checks}/#{current_domains.length} successful"
              rescue StandardError => e
                logger.error "Domain check cycle failed: #{e.message}"
                logger.error e.backtrace.join("\n")
              end
            end
          end
        rescue StandardError => e
          logger.error "Async checker thread crashed: #{e.message}"
          logger.error e.backtrace.join("\n")
          logger.info 'Restarting async checker thread in 10 seconds...'
          sleep 10
          retry
        end
        logger.debug '[AsyncChecker] Thread exiting.'
      end
      logger.info 'Async domain checker thread started successfully'
    end

    def start_exporter
      logger.debug 'Starting metrics exporter...'
      # 设置 Sinatra 服务器选项
      Exporter.set :port, Config.metrics_port
      Exporter.run! host: '0.0.0.0'
    end
  end
end
