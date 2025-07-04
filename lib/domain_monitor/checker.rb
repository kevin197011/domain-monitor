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

    def check_all_domains
      return if @config.domains.empty?

      @logger.info "Starting domain check for #{@config.domains.size} domains"

      # 使用线程池并发检查域名
      thread_pool = Concurrent::FixedThreadPool.new(@config.max_concurrent_checks)
      futures = []

      @config.domains.each do |domain|
        futures << Concurrent::Future.execute(executor: thread_pool) do
          check_domain(domain)
        end
      end

      # 等待所有检查完成
      futures.each(&:wait)
      thread_pool.shutdown
      thread_pool.wait_for_termination(30)

      @logger.info 'Domain check cycle completed'
    rescue StandardError => e
      @logger.error "Error in domain check cycle: #{e.message}"
      @logger.debug e.backtrace.join("\n")
    ensure
      thread_pool&.shutdown
    end

    def check_domain(domain)
      @logger.debug "Checking domain: #{domain}"

      result = @whois_client.check_domain(domain)

      @metrics_mutex.synchronize do
        @domain_metrics[domain] = result
      end

      if result[:error]
        @logger.warn "Failed to check domain #{domain}: #{result[:error]}"
      else
        status = result[:days_until_expiry] <= @config.expire_threshold_days ? 'CRITICAL' : 'OK'
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
