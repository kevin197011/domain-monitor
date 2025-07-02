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
      @logger.info "开始检查域名: #{domain}"

      begin
        Timeout.timeout(15) do # 设置整体超时
          @logger.debug "正在查询 WHOIS 服务器: #{domain}"
          record = @client.lookup(domain)

          # 处理响应内容的编码
          content = normalize_encoding(record.content)
          @logger.debug "获取到 WHOIS 响应:\n#{content}"

          # 尝试从响应中提取过期日期
          expiration_date = extract_expiration_date(content)

          if expiration_date
            days_until_expiry = (expiration_date.to_date - Date.today).to_i
            @logger.info "域名 #{domain} 将在 #{days_until_expiry} 天后过期 (#{expiration_date})"

            {
              domain: domain,
              expiration_date: expiration_date,
              days_until_expiry: days_until_expiry,
              status: :success
            }
          else
            @logger.error "无法从 WHOIS 响应中提取过期日期: #{domain}"
            {
              domain: domain,
              status: :error,
              error: '无法提取过期日期'
            }
          end
        end
      rescue Timeout::Error => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "查询域名 #{domain} 超时 (第 #{retries}/#{@config.whois_retry_times} 次尝试): #{e.message}"
          sleep @config.whois_retry_interval
          retry
        end

        @logger.error "在 #{retries} 次尝试后查询域名 #{domain} 失败: 超时"
        {
          domain: domain,
          status: :error,
          error: "#{retries} 次尝试后超时"
        }
      rescue StandardError => e
        retries += 1
        if retries <= @config.whois_retry_times
          @logger.warn "查询域名 #{domain} 出错 (第 #{retries}/#{@config.whois_retry_times} 次尝试): #{e.message}"
          sleep @config.whois_retry_interval
          retry
        end

        @logger.error "在 #{retries} 次尝试后查询域名 #{domain} 失败: #{e.message}"
        @logger.error e.backtrace.join("\n")
        {
          domain: domain,
          status: :error,
          error: e.message
        }
      end
    end

    private

    def normalize_encoding(content)
      # 尝试检测编码
      if content.encoding == Encoding::ASCII_8BIT
        # 尝试不同的编码
        %w[UTF-8 GBK GB18030 GB2312].each do |encoding|
          decoded = content.force_encoding(encoding)
          if decoded.valid_encoding?
            @logger.debug "成功使用 #{encoding} 解码响应"
            return decoded.encode('UTF-8')
          end
        rescue EncodingError => e
          @logger.debug "使用 #{encoding} 解码失败: #{e.message}"
        end

        # 如果所有尝试都失败，强制转换为 UTF-8 并替换无效字符
        @logger.debug '使用 UTF-8 编码并替换无效字符'
        content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      else
        content
      end
    end

    def extract_expiration_date(content)
      # 常见的过期日期字段
      date_patterns = [
        # 中文格式
        /(?:过期时间|到期时间)[:：]\s*(.+?)(?:\n|$)/i,
        /(?:过期日期|到期日期)[:：]\s*(.+?)(?:\n|$)/i,

        # 英文格式
        /(?:Expiry Date|Expiration Date|Registry Expiry Date):\s*(.+?)(?:\n|$)/i,
        /(?:Registrar Registration Expiration Date):\s*(.+?)(?:\n|$)/i,
        /(?:Domain Expiration Date):\s*(.+?)(?:\n|$)/i,

        # 其他格式
        /Expiry\s*[=:]\s*(.+?)(?:\n|$)/i,
        /expires\s*[=:]\s*(.+?)(?:\n|$)/i
      ]

      date_patterns.each do |pattern|
        next unless (match = content.match(pattern))

        begin
          date_str = match[1].strip
          @logger.debug "尝试解析日期字符串: '#{date_str}'"

          # 处理常见的日期格式
          date_str = date_str.sub(/\s*\([^)]*\)/, '') # 移除括号中的内容
          date_str = date_str.sub(/\.\d+Z?$/, '') # 移除毫秒
          date_str = date_str.sub(/[A-Z]{3,4}$/, '') # 移除时区缩写

          # 尝试解析日期
          date = DateTime.parse(date_str)
          @logger.debug "成功解析到过期日期: #{date}"
          return date
        rescue ArgumentError => e
          @logger.debug "解析日期 '#{date_str}' 失败: #{e.message}"
          next
        end
      end

      @logger.debug '在 WHOIS 响应中未找到过期日期'
      nil
    end
  end
end
