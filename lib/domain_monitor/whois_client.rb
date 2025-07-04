# frozen_string_literal: true

module DomainMonitor
  class WhoisClient
    def initialize(config)
      @config = config
      @logger = Logger.create('WhoisClient')
      @whois = Whois::Client.new
    end

    def check_domain(domain)
      @logger.debug "Checking domain: #{domain}"

      retries = 0
      begin
        response = nil
        Timeout.timeout(30) do
          response = @whois.lookup(domain)
        end

        if response&.parser&.expires_on
          expiry_date = response.parser.expires_on
          days_until_expiry = calculate_days_until_expiry(expiry_date)

          result = {
            domain: domain,
            days_until_expiry: days_until_expiry,
            expiry_date: expiry_date.to_s,
            error: nil,
            last_checked: Time.now.to_f
          }

          @logger.debug "Domain #{domain} expires on #{expiry_date} (#{days_until_expiry} days)"
          result
        else
          {
            domain: domain,
            days_until_expiry: -1,
            expiry_date: nil,
            error: 'No expiry date found',
            last_checked: Time.now.to_f
          }
        end
      rescue Timeout::Error => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "Timeout checking #{domain}, retrying (#{retries}/#{@config.whois_retry_times})"
          sleep(@config.whois_retry_interval)
          retry
        end

        @logger.error "Timeout checking domain #{domain} after #{@config.whois_retry_times} retries"
        {
          domain: domain,
          days_until_expiry: -1,
          expiry_date: nil,
          error: 'Timeout after retries',
          last_checked: Time.now.to_f
        }
      rescue StandardError => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "Error checking #{domain}: #{e.message}, retrying (#{retries}/#{@config.whois_retry_times})"
          sleep(@config.whois_retry_interval)
          retry
        end

        @logger.error "Failed to check domain #{domain} after #{@config.whois_retry_times} retries: #{e.message}"
        {
          domain: domain,
          days_until_expiry: -1,
          expiry_date: nil,
          error: e.message,
          last_checked: Time.now.to_f
        }
      end
    end

    private

    def calculate_days_until_expiry(expiry_date)
      return -1 unless expiry_date

      days = (expiry_date.to_date - Date.today).to_i
      [days, 0].max # 确保不返回负数（除了错误情况）
    end
  end
end
