# frozen_string_literal: true

require 'concurrent'
require 'logger'

module DomainMonitor
  class Checker
    DEFAULT_THREAD_POOL_SIZE = 50

    def initialize(config = Config.instance)
      @config = config
      @logger = Logger.new($stdout)
      @whois_client = WhoisClient.new(config)
      @check_results = Concurrent::Map.new
      @running = false
      @checking = false

      # 创建固定大小的线程池
      @thread_pool = Concurrent::FixedThreadPool.new(
        ENV.fetch('DOMAIN_CHECK_THREADS', DEFAULT_THREAD_POOL_SIZE).to_i
      )
    end

    def start
      @logger.info 'Starting domain checker...'
      @running = true

      # 立即执行第一次检查
      perform_check

      # Start checking thread
      @check_thread = Thread.new do
        while @running
          begin
            sleep @config.check_interval
            perform_check
          rescue StandardError => e
            @logger.error "Error in check thread: #{e.message}"
            @logger.error e.backtrace.join("\n")
          end
        end
      end
    end

    def stop
      @logger.info 'Stopping domain checker...'
      @running = false
      @check_thread&.join

      # 关闭线程池
      @thread_pool.shutdown
      @thread_pool.wait_for_termination(10) # 等待最多10秒完成当前任务
    end

    def results
      # 如果没有结果且不在检查中，返回空状态
      if @check_results.empty? && !@checking
        @logger.debug '没有检查结果，执行立即检查'
        perform_check
      end

      # 将 Concurrent::Map 转换为普通 Hash
      result_hash = {}
      @check_results.each_pair do |key, value|
        result_hash[key] = value
      end

      # 如果仍然没有结果，返回等待状态
      if result_hash.empty? && !@config.domains.empty?
        @config.domains.each do |domain_config|
          result_hash[domain_config[:domain]] = {
            expire_days: nil,
            expired: false,
            check_status: false,
            last_check: Time.now,
            error: @checking ? '检查进行中' : '等待检查'
          }
        end
      end

      result_hash
    end

    private

    def perform_check
      return if @checking || @config.domains.empty?

      @checking = true
      @logger.info "检查 #{@config.domains.size} 个域名..."

      # 使用 Promise.all 等待所有检查完成
      promises = @config.domains.map do |domain_config|
        Concurrent::Promise.execute(executor: @thread_pool) do
          check_single_domain(domain_config)
        end
      end

      # 等待所有检查完成
      begin
        results = Concurrent::Promise.zip(*promises).value!(30) # 设置30秒超时
        success_count = results.count { |r| r && r[:check_status] }
        @logger.info "域名检查完成: #{success_count}/#{results.size} 成功"
      rescue Concurrent::TimeoutError
        @logger.error '域名检查超时（30秒）'
      rescue StandardError => e
        @logger.error "域名检查出错: #{e.message}"
        @logger.error e.backtrace.join("\n")
      ensure
        @checking = false
      end
    end

    def check_single_domain(domain_config)
      domain = domain_config[:domain]
      check_result = @whois_client.check_domain(domain)

      result = {
        expire_days: check_result[:days_until_expiry],
        expired: check_result[:days_until_expiry] && check_result[:days_until_expiry] <= @config.expire_threshold_days,
        check_status: check_result[:status] == :success,
        last_check: Time.now,
        error: check_result[:error]
      }

      @check_results[domain] = result
      log_check_result(domain, check_result)

      # 返回结果用于统计
      result
    rescue StandardError => e
      @logger.error "检查域名 #{domain} 时出错: #{e.message}"
      @logger.error e.backtrace.join("\n")

      result = {
        expire_days: nil,
        expired: false,
        check_status: false,
        last_check: Time.now,
        error: e.message
      }

      @check_results[domain] = result
      result
    end

    def log_check_result(domain, result)
      if result[:status] == :success
        @logger.info "域名 #{domain}: #{result[:days_until_expiry]} 天后过期"
      else
        @logger.error "域名 #{domain} 检查失败: #{result[:error]}"
      end
    end
  end
end
