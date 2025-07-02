# frozen_string_literal: true

require 'concurrent'
require 'logger'

module DomainMonitor
  class Checker
    DEFAULT_THREAD_POOL_SIZE = 50
    INITIAL_WAIT_TIME = 60 # Initial wait time in seconds

    def initialize(config = Config.instance)
      @config = config
      @logger = config.create_logger('Checker')
      @whois_client = WhoisClient.new(config)
      @check_results = Concurrent::Map.new
      @running = false
      @checking = false
      @initial_check_completed = false

      # Create fixed size thread pool
      @thread_pool = Concurrent::FixedThreadPool.new(
        ENV.fetch('DOMAIN_CHECK_THREADS', @config.max_concurrent_checks).to_i
      )
    end

    def start
      @logger.info 'Starting domain checker'
      @running = true

      # Start checking thread
      @check_thread = Thread.new do
        # Initial check with delay
        @logger.info "Waiting #{INITIAL_WAIT_TIME} seconds before first check"
        sleep INITIAL_WAIT_TIME
        perform_check
        @initial_check_completed = true

        # Continue with regular checks
        while @running
          begin
            sleep @config.check_interval
            perform_check
          rescue StandardError => e
            @logger.error "Check thread error: #{e.message}"
            @logger.debug e.backtrace.join("\n")
          end
        end
      end
    end

    def stop
      @logger.info 'Stopping domain checker'
      @running = false
      @check_thread&.join

      # Shutdown thread pool
      @thread_pool.shutdown
      @thread_pool.wait_for_termination(10) # Wait up to 10 seconds for completion
      @logger.info 'Domain checker stopped'
    end

    def results
      # If no results and not checking, return empty status
      if @check_results.empty? && !@checking
        if !@initial_check_completed
          @logger.debug 'Waiting for initial check to complete'
          # Return waiting status for all domains
          result_hash = {}
          @config.domains.each do |domain|
            result_hash[domain] = {
              expire_days: nil,
              expired: false,
              check_status: false,
              last_check: Time.now,
              error: 'Waiting for initial check'
            }
          end
          return result_hash
        else
          @logger.debug 'No check results, performing immediate check'
          perform_check
        end
      end

      # Convert Concurrent::Map to regular Hash
      result_hash = {}
      @check_results.each_pair do |key, value|
        result_hash[key] = value
      end

      # If still no results but have domains, return waiting status
      if result_hash.empty? && !@config.domains.empty?
        @config.domains.each do |domain|
          result_hash[domain] = {
            expire_days: nil,
            expired: false,
            check_status: false,
            last_check: Time.now,
            error: @checking ? 'Check in progress' : 'Waiting for check'
          }
        end
      end

      result_hash
    end

    private

    def perform_check
      return if @checking || @config.domains.empty?

      @checking = true
      @logger.info "Starting check for #{@config.domains.size} domains"

      # Use Promise.all to wait for all checks to complete
      promises = @config.domains.map do |domain|
        Concurrent::Promise.execute(executor: @thread_pool) do
          check_single_domain(domain)
        end
      end

      # Wait for all checks to complete
      begin
        results = Concurrent::Promise.zip(*promises).value!(30) # Set 30 seconds timeout
        success_count = results.count { |r| r && r[:check_status] }
        @logger.info "Domain check completed: #{success_count}/#{results.size} successful"
      rescue Concurrent::TimeoutError
        @logger.error 'Domain check timeout (30 seconds)'
      rescue StandardError => e
        @logger.error "Domain check error: #{e.message}"
        @logger.debug e.backtrace.join("\n")
      ensure
        @checking = false
      end
    end

    def check_single_domain(domain)
      @logger.debug "Checking domain: #{domain}"
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

      # Return result for statistics
      result
    rescue StandardError => e
      @logger.error "Error checking domain #{domain}: #{e.message}"
      @logger.debug e.backtrace.join("\n")

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
        @logger.info "Domain #{domain}: #{result[:days_until_expiry]} days until expiry"
      else
        @logger.error "Domain #{domain} check failed: #{result[:error]}"
      end
    end
  end
end
