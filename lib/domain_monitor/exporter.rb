# frozen_string_literal: true

require 'set'
require 'prometheus/client'

module DomainMonitor
  class Exporter
    attr_reader :prometheus

    def initialize
      @prometheus = Prometheus::Client.registry
      @expire_days = safe_gauge(:domain_expire_days,
                                docstring: 'Days until domain expiration (-1 if check failed)',
                                labels: %i[domain])
      @expired = safe_gauge(:domain_expired,
                            docstring: 'Whether domain is expired or close to expiry (1) or not (0)',
                            labels: %i[domain])
      @check_status = safe_gauge(:domain_check_status,
                                 docstring: 'Check status (1: success, 0: error)',
                                 labels: %i[domain])
      @last_domains = Set.new
    end

    def update_expire_days(domain, days)
      @expire_days.set(days, labels: { domain: domain })
    end

    def update_expired_status(domain, is_expired)
      @expired.set(is_expired ? 1 : 0, labels: { domain: domain })
    end

    def update_check_status(domain, success)
      @check_status.set(success ? 1 : 0, labels: { domain: domain })
    end

    def update_metrics(checker)
      current_domains = checker.domain_metrics.keys.to_set
      # removed_domains = @last_domains - current_domains
      # removed_domains.each do |domain|
      #   @expire_days.set(-1, labels: { domain: domain })
      #   @expired.set(0, labels: { domain: domain })
      #   @check_status.set(0, labels: { domain: domain })
      # end
      checker.domain_metrics.each do |domain, metrics|
        next unless metrics

        if metrics[:error]
          update_expire_days(domain, -1)
          update_expired_status(domain, false)
          update_check_status(domain, false)
        else
          days_until_expiry = metrics[:days_until_expiry] || -1
          update_expire_days(domain, days_until_expiry)
          is_expired_or_close = days_until_expiry >= 0 && days_until_expiry <= Config.expire_threshold_days
          update_expired_status(domain, is_expired_or_close)
          update_check_status(domain, true)
        end
      end
      @last_domains = current_domains
      # 新增 info 日志
      error_count = checker.domain_metrics.values.count { |m| m[:error] }
      DomainMonitor::Logger.instance.info "Exporter updated metrics: domains=#{current_domains.size}, error_domains=#{error_count}"
    end

    private

    def safe_gauge(name, docstring:, labels:)
      if @prometheus.exist?(name)
        @prometheus.get(name)
      else
        gauge = Prometheus::Client::Gauge.new(name, docstring: docstring, labels: labels)
        @prometheus.register(gauge)
        gauge
      end
    end
  end
end
