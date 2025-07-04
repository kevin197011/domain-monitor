# frozen_string_literal: true

module DomainMonitor
  class Checker
    attr_reader :domain_metrics

    def initialize(config)
      @config = config
      @logger = Logger.create('Checker')
      @whois_client = WhoisClient.new(@config)
      @domain_metrics = {}
      @metrics_mutex = Mutex.new

      # 初始化所有域名的指标
      initialize_domain_metrics
    end

    def check_all_domains(override_config = nil)
      # 使用传入的配置或默认配置
      current_config = override_config || @config
      current_domains = current_config.domains

      return if current_domains.empty?

      max_concurrent = current_config.max_concurrent_checks
      @logger.info "Starting domain check for #{current_domains.size} domains (concurrency: #{max_concurrent})"

      # 使用线程池并发检查域名，并发数基于当前配置
      thread_pool = Concurrent::FixedThreadPool.new(max_concurrent)
      futures = []

      current_domains.each do |domain|
        futures << Concurrent::Future.execute(executor: thread_pool) do
          check_domain(domain, current_config)
        end
      end

      # 等待所有检查完成
      futures.each(&:wait)
      thread_pool.shutdown
      thread_pool.wait_for_termination(30)

      @logger.debug "Domain check cycle completed using #{max_concurrent} concurrent threads"
    rescue StandardError => e
      @logger.error "Error in domain check cycle: #{e.message}"
      @logger.debug e.backtrace.join("\n")
    ensure
      thread_pool&.shutdown
    end

    def check_domain(domain, config = nil)
      current_config = config || @config
      @logger.debug "Checking domain: #{domain}"

      result = @whois_client.check_domain(domain)

      @metrics_mutex.synchronize do
        @domain_metrics[domain] = result
      end

      if result[:error]
        @logger.warn "Failed to check domain #{domain}: #{result[:error]}"
      else
        status = result[:days_until_expiry] <= current_config.expire_threshold_days ? 'CRITICAL' : 'OK'
        @logger.debug "Domain #{domain}: #{result[:days_until_expiry]} days until expiry (#{status})"
      end

      result
    rescue StandardError => e
      error_result = {
        domain: domain,
        days_until_expiry: -1,
        expiry_date: nil,
        error: e.message,
        last_checked: Time.now.to_f
      }

      @metrics_mutex.synchronize do
        @domain_metrics[domain] = error_result
      end

      @logger.error "Error checking domain #{domain}: #{e.message}"
      error_result
    end

    def get_domain_metrics
      @metrics_mutex.synchronize do
        @domain_metrics.dup
      end
    end

    def get_summary_metrics
      metrics = get_domain_metrics

      {
        total_domains: metrics.size,
        successful_checks: metrics.count { |_, m| m[:status] == 'success' },
        failed_checks: metrics.count { |_, m| m[:status] == 'error' },
        expired_domains: metrics.count { |_, m| m[:is_expired] },
        expiring_soon_domains: metrics.count { |_, m| m[:will_expire_soon] },
        last_check_time: metrics.values.map { |m| m[:last_check] }.compact.max
      }
    end

    # 更新内部域名列表，清理不再监控的域名指标
    def update_domain_list(new_domains)
      @metrics_mutex.synchronize do
        # 移除不再监控的域名
        @domain_metrics.each_key do |domain|
          @domain_metrics.delete(domain) unless new_domains.include?(domain)
        end

        # 初始化新域名的指标
        new_domains.each do |domain|
          next if @domain_metrics.key?(domain)

          @domain_metrics[domain] = {
            domain: domain,
            days_until_expiry: 0,
            expiry_date: nil,
            error: nil,
            last_checked: 0
          }
        end
      end

      @logger.debug "Updated domain list: #{new_domains.size} domains"
    end

    private

    def initialize_domain_metrics
      @config.domains.each do |domain|
        @domain_metrics[domain] = {
          domain: domain,
          days_until_expiry: 0,
          expiry_date: nil,
          error: nil,
          last_checked: 0
        }
      end
    end

    def calculate_days_to_expire(expiry_date)
      return nil unless expiry_date

      case expiry_date
      when String
        begin
          parsed_date = Date.parse(expiry_date)
          (parsed_date - Date.today).to_i
        rescue StandardError
          nil
        end
      when Date
        (expiry_date - Date.today).to_i
      when Time
        (expiry_date.to_date - Date.today).to_i
      end
    end
  end
end
