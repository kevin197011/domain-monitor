# frozen_string_literal: true

module DomainMonitor
  # Prometheus metrics exporter
  class Exporter < Sinatra::Base
    # 设置 Puma 作为服务器
    set :server, :puma
    # 监听所有地址
    set :bind, '0.0.0.0'
    # 设置环境为生产环境
    set :environment, :production

    # 创建注册表
    prometheus = Prometheus::Client.registry

    # 定义指标
    EXPIRE_DAYS = Prometheus::Client::Gauge.new(:domain_expire_days,
                                                docstring: 'Days until domain expiration (-1 if check failed)',
                                                labels: %i[domain])
    EXPIRED = Prometheus::Client::Gauge.new(:domain_expired,
                                            docstring: 'Whether domain is expired or close to expiry (1) or not (0)',
                                            labels: %i[domain])
    CHECK_STATUS = Prometheus::Client::Gauge.new(:domain_check_status,
                                                 docstring: 'Check status (1: success, 0: error)',
                                                 labels: %i[domain])

    # 注册指标
    prometheus.register(EXPIRE_DAYS)
    prometheus.register(EXPIRED)
    prometheus.register(CHECK_STATUS)

    # 健康检查端点
    get '/health' do
      'OK'
    end

    # 指标导出端点
    get '/metrics' do
      content_type 'text/plain; version=0.0.4'
      Prometheus::Client::Formats::Text.marshal(prometheus)
    end

    # 更新域名过期天数指标
    def self.update_expire_days(domain, days)
      EXPIRE_DAYS.set(days, labels: { domain: domain })
    end

    # 更新域名过期状态指标
    def self.update_expired_status(domain, is_expired)
      EXPIRED.set(is_expired ? 1 : 0, labels: { domain: domain })
    end

    # 更新域名检查状态指标
    def self.update_check_status(domain, success)
      CHECK_STATUS.set(success ? 1 : 0, labels: { domain: domain })
    end

    require 'set'
    @last_domains ||= Set.new

    # 批量更新所有指标
    def self.update_metrics(checker)
      current_domains = checker.domain_metrics.keys.to_set

      # 清理已被移除的域名指标
      removed_domains = @last_domains - current_domains
      removed_domains.each do |domain|
        EXPIRE_DAYS.remove(labels: { domain: domain })
        EXPIRED.remove(labels: { domain: domain })
        CHECK_STATUS.remove(labels: { domain: domain })
      end

      checker.domain_metrics.each do |domain, metrics|
        next unless metrics

        if metrics[:error]
          # 检查失败
          update_expire_days(domain, -1)
          update_expired_status(domain, false)
          update_check_status(domain, false)
        else
          # 检查成功
          days_until_expiry = metrics[:days_until_expiry] || -1
          update_expire_days(domain, days_until_expiry)

          # 判断是否过期或接近过期
          is_expired_or_close = days_until_expiry >= 0 && days_until_expiry <= Config.expire_threshold_days
          update_expired_status(domain, is_expired_or_close)

          update_check_status(domain, true)
        end
      end

      @last_domains = current_domains
    end
  end
end
