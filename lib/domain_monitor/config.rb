# frozen_string_literal: true

require 'dotenv'
require 'yaml'
require 'singleton'
require 'logger'

module DomainMonitor
  class Config
    include Singleton

    # Nacos 连接配置
    attr_reader :nacos_addr, :nacos_namespace, :nacos_group, :nacos_data_id

    # 应用配置（从 Nacos 获取）
    attr_reader :domains, :whois_retry_times, :whois_retry_interval,
                :check_interval, :expire_threshold_days, :check_threads,
                :metrics_port

    DEFAULT_CONFIG = {
      whois_retry_times: 3,
      whois_retry_interval: 5,
      check_interval: 3600,
      expire_threshold_days: 1,
      check_threads: 50,
      metrics_port: 9394
    }.freeze

    def initialize
      load_nacos_config
      set_default_values
    end

    def load_nacos_config
      Dotenv.load

      @nacos_addr = ENV['NACOS_ADDR'] || 'http://localhost:8848'
      @nacos_namespace = ENV['NACOS_NAMESPACE'] || 'dev'
      @nacos_group = ENV['NACOS_GROUP'] || 'DEFAULT_GROUP'
      @nacos_data_id = ENV['NACOS_DATA_ID'] || 'domain_monitor.yml'
    end

    def update_domains_config(yaml_content)
      return unless yaml_content

      config = YAML.safe_load(yaml_content, symbolize_names: true)

      # 更新域名列表
      @domains = (config[:domains] || []).map { |domain| { domain: domain } }

      # 更新全局设置
      settings = config[:settings] || {}
      update_settings(settings)

      log_current_config
    end

    private

    def set_default_values
      @domains = []
      update_settings({})
    end

    def update_settings(settings)
      @whois_retry_times = settings[:whois_retry_times] || DEFAULT_CONFIG[:whois_retry_times]
      @whois_retry_interval = settings[:whois_retry_interval] || DEFAULT_CONFIG[:whois_retry_interval]
      @check_interval = settings[:check_interval] || DEFAULT_CONFIG[:check_interval]
      @expire_threshold_days = settings[:expire_threshold_days] || DEFAULT_CONFIG[:expire_threshold_days]
      @check_threads = settings[:check_threads] || DEFAULT_CONFIG[:check_threads]
      @metrics_port = settings[:metrics_port] || DEFAULT_CONFIG[:metrics_port]
    end

    def log_current_config
      logger = Logger.new($stdout)
      logger.info 'Current configuration:'
      logger.info "- Domains: #{@domains.map { |d| d[:domain] }.join(', ')}"
      logger.info "- WHOIS retry times: #{@whois_retry_times}"
      logger.info "- WHOIS retry interval: #{@whois_retry_interval}s"
      logger.info "- Check interval: #{@check_interval}s"
      logger.info "- Expire threshold days: #{@expire_threshold_days}"
      logger.info "- Check threads: #{@check_threads}"
      logger.info "- Metrics port: #{@metrics_port}"
    end
  end
end
