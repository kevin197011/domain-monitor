# frozen_string_literal: true

require 'whois'
require 'logger'
require 'date'
require 'timeout'

module DomainMonitor
  class WhoisClient
    def initialize(config = Config.instance)
      @config = config
      @logger = config.create_logger('WHOIS')
      @client = Whois::Client.new(timeout: 10)

      # 设置日志级别为 DEBUG
      @logger.level = Logger::INFO
    end

    def check_domain(domain)
      retries = 0
      @logger.info "Starting WHOIS query for domain: #{domain}"

      begin
        Timeout.timeout(15) do # Set overall timeout
          @logger.debug "Querying WHOIS server for domain: #{domain}"
          record = @client.lookup(domain)

          # Handle response encoding
          content = normalize_encoding(record.content)
          @logger.debug "WHOIS response received for domain: #{domain}"

          # Try to extract expiration date from response
          expiration_date = extract_expiration_date(content)

          if expiration_date
            days_until_expiry = (expiration_date.to_date - Date.today).to_i
            @logger.info "Domain #{domain} will expire in #{days_until_expiry} days (#{expiration_date})"

            {
              domain: domain,
              expiration_date: expiration_date,
              days_until_expiry: days_until_expiry,
              status: :success
            }
          else
            @logger.error "Could not extract expiration date for domain: #{domain}"
            {
              domain: domain,
              status: :error,
              error: 'Could not extract expiration date'
            }
          end
        end
      rescue Timeout::Error => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "WHOIS query timeout for #{domain} (attempt #{retries}/#{@config.whois_retry_times})"
          sleep @config.whois_retry_interval
          retry
        end

        @logger.error "WHOIS query failed for #{domain} after #{retries} attempts: timeout"
        {
          domain: domain,
          status: :error,
          error: "Timeout after #{retries} attempts"
        }
      rescue StandardError => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "WHOIS query error for #{domain} (attempt #{retries}/#{@config.whois_retry_times}): #{e.message}"
          sleep @config.whois_retry_interval
          retry
        end

        @logger.error "WHOIS query failed for #{domain} after #{retries} attempts: #{e.message}"
        @logger.debug e.backtrace.join("\n")
        {
          domain: domain,
          status: :error,
          error: e.message
        }
      end
    end

    private

    def normalize_encoding(content)
      # Try to detect encoding
      if content.encoding == Encoding::ASCII_8BIT
        # Try different encodings
        %w[UTF-8 GBK GB18030 GB2312].each do |encoding|
          decoded = content.force_encoding(encoding)
          if decoded.valid_encoding?
            @logger.debug "Successfully decoded response using #{encoding}"
            return decoded.encode('UTF-8')
          end
        rescue EncodingError => e
          @logger.debug "Failed to decode using #{encoding}: #{e.message}"
        end

        # If all attempts fail, force UTF-8 and replace invalid characters
        @logger.debug 'Using UTF-8 encoding with replacement for invalid characters'
        content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      else
        content
      end
    end

    def extract_expiration_date(content)
      # Common expiration date patterns
      date_patterns = [
        # English formats
        /(?:Expiry Date|Expiration Date|Registry Expiry Date):\s*(.+?)(?:\n|$)/i,
        /(?:Registrar Registration Expiration Date):\s*(.+?)(?:\n|$)/i,
        /(?:Domain Expiration Date):\s*(.+?)(?:\n|$)/i,

        # Other formats
        /Expiry\s*[=:]\s*(.+?)(?:\n|$)/i,
        /expires\s*[=:]\s*(.+?)(?:\n|$)/i
      ]

      date_patterns.each do |pattern|
        next unless (match = content.match(pattern))

        begin
          date_str = match[1].strip
          @logger.debug "Attempting to parse date string: '#{date_str}'"

          # Handle common date formats
          date_str = date_str.sub(/\s*\([^)]*\)/, '') # Remove content in parentheses
          date_str = date_str.sub(/\.\d+Z?$/, '') # Remove milliseconds
          date_str = date_str.sub(/[A-Z]{3,4}$/, '') # Remove timezone abbreviation

          # Try to parse date
          date = DateTime.parse(date_str)
          @logger.debug "Successfully parsed expiration date: #{date}"
          return date
        rescue ArgumentError => e
          @logger.debug "Failed to parse date '#{date_str}': #{e.message}"
          next
        end
      end

      @logger.debug 'No expiration date found in WHOIS response'
      nil
    end
  end
end
