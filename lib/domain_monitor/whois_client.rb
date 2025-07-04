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

        # Try to parse the response to get expiry date
        begin
          expiry_date = extract_expiry_date(response, domain)

          if expiry_date
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
            @logger.debug "Failed to extract expiry date from WHOIS response for #{domain}"
            {
              domain: domain,
              days_until_expiry: -1,
              expiry_date: nil,
              error: 'No expiry date found in WHOIS response',
              last_checked: Time.now.to_f
            }
          end
        rescue StandardError => e
          @logger.warn "Failed to parse WHOIS response for #{domain}: #{e.message}"
          @logger.debug "Parser error details: #{e.class} - #{e.backtrace.first}"
          {
            domain: domain,
            days_until_expiry: -1,
            expiry_date: nil,
            error: "Parse error: #{e.message}",
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

    def extract_expiry_date(response, domain)
      # 方法1: 使用标准parser
      begin
        parser = response.parser
        if parser.respond_to?(:expires_on) && parser.expires_on
          @logger.debug "Method 1 (parser.expires_on) succeeded for #{domain}"
          return parser.expires_on
        end
      rescue StandardError => e
        @logger.debug "Method 1 (parser.expires_on) failed for #{domain}: #{e.message}"
      end

      # 方法2: 尝试其他parser方法
      begin
        parser = response.parser
        %w[expiry_date expiration_date expires_at expiry expires].each do |method|
          next unless parser.respond_to?(method.to_sym)

          result = parser.send(method.to_sym)
          if result
            @logger.debug "Method 2 (parser.#{method}) succeeded for #{domain}"
            return result
          end
        end
      rescue StandardError => e
        @logger.debug "Method 2 (alternative parser methods) failed for #{domain}: #{e.message}"
      end

      # 方法3: 直接解析WHOIS文本
      begin
        whois_text = response.to_s
        expiry_date = parse_whois_text(whois_text, domain)
        if expiry_date
          @logger.debug "Method 3 (text parsing) succeeded for #{domain}"
          return expiry_date
        end
      rescue StandardError => e
        @logger.debug "Method 3 (text parsing) failed for #{domain}: #{e.message}"
      end

      @logger.debug "All parsing methods failed for #{domain}"
      nil
    end

    def parse_whois_text(whois_text, domain)
      # 常见的过期日期格式和字段名
      patterns = [
        /expir(?:y|ation|es)\s*(?:date|time)?\s*:\s*(.+)/i,
        /renewal\s*date\s*:\s*(.+)/i,
        /expires?\s*(?:on|at)?\s*:\s*(.+)/i,
        /expir(?:y|ation)\s*:\s*(.+)/i,
        /valid\s*until\s*:\s*(.+)/i,
        /registry\s*expir(?:y|ation)\s*date\s*:\s*(.+)/i,
        /registrar\s*expir(?:y|ation)\s*date\s*:\s*(.+)/i
      ]

      patterns.each do |pattern|
        match = whois_text.match(pattern)
        next unless match

        date_string = match[1].strip
        @logger.debug "Found potential expiry date for #{domain}: '#{date_string}'"

        parsed_date = parse_date_string(date_string)
        return parsed_date if parsed_date
      end

      @logger.debug "No expiry date patterns matched for #{domain}"
      @logger.debug "WHOIS response preview: #{whois_text[0, 500]}..." if whois_text.length > 500
      nil
    end

    def parse_date_string(date_string)
      # 清理日期字符串
      cleaned = date_string.gsub(/\s+/, ' ').strip

      # 常见日期格式
      formats = [
        '%Y-%m-%d',
        '%Y-%m-%d %H:%M:%S',
        '%Y-%m-%dT%H:%M:%S',
        '%Y-%m-%dT%H:%M:%SZ',
        '%Y-%m-%d %H:%M:%S %Z',
        '%d-%m-%Y',
        '%d/%m/%Y',
        '%m/%d/%Y',
        '%d.%m.%Y',
        '%Y.%m.%d',
        '%d-%b-%Y',
        '%d %b %Y',
        '%b %d %Y',
        '%B %d, %Y'
      ]

      formats.each do |format|
        return Date.strptime(cleaned, format)
      rescue ArgumentError
        # 继续尝试下一个格式
      end

      # 尝试自动解析
      begin
        Date.parse(cleaned)
      rescue ArgumentError
        nil
      end
    end

    def calculate_days_until_expiry(expiry_date)
      return -1 unless expiry_date

      days = (expiry_date.to_date - Date.today).to_i
      [days, 0].max # 确保不返回负数（除了错误情况）
    end
  end
end
