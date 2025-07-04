# frozen_string_literal: true

module DomainMonitor
  # Main application class that handles initialization and startup
  class Application
    attr_reader :logger, :nacos_client, :checker

    def initialize
      @logger = Logger.create('System')
      @logger.level = ::Logger::INFO # 初始设置为 INFO，后续从配置更新
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

      # 首次同步检查
      logger.info 'Starting domain checker...'
      @checker.check_all_domains

      # 更新首次检查的指标
      Exporter.update_metrics(@checker)
      successful_checks = @checker.domain_metrics.count { |_, m| !m[:error] }
      logger.info "Initial domain check completed: #{successful_checks}/#{Config.domains.length} successful"

      # 启动异步检查线程
      start_checker_thread

      # 启动指标服务器
      start_exporter
    rescue StandardError => e
      logger.error "Startup failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      exit 1
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
      @nacos_client.start_listening
    end

    def start_checker_thread
      logger.info 'Starting domain checker thread...'
      Thread.new do
        # 等待一个检查周期后开始异步检查
        sleep Config.check_interval

        loop do
          logger.info "Scheduled check: Checking #{Config.domains.length} domains..."

          begin
            # 执行域名检查
            @checker.check_all_domains

            # 更新指标
            Exporter.update_metrics(@checker)
            successful_checks = @checker.domain_metrics.count { |_, m| !m[:error] }
            logger.info "Scheduled domain check completed: #{successful_checks}/#{Config.domains.length} successful"
          rescue StandardError => e
            logger.error "Domain check cycle failed: #{e.message}"
            logger.error e.backtrace.join("\n")
          end

          # 等待下一个检查周期
          sleep Config.check_interval
        end
      rescue StandardError => e
        logger.error "Checker thread crashed: #{e.message}"
        logger.error e.backtrace.join("\n")
        # 重启线程
        sleep 10
        retry
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
