# frozen_string_literal: true

#
# Domain Monitor - Ruby Gem for Domain Expiration Monitoring
#
# 依赖加载规范 (RG1-RG5)：
# 1. 所有外部gem依赖在此入口文件集中加载
# 2. 子模块采用惰性加载(autoload)以提升性能
# 3. 条件化加载可选功能模块(Nacos, Prometheus)
# 4. 避免重复加载，使用 defined? 检查
#
# 外部依赖清单：
# - logger: 标准库日志
# - yaml/psych: YAML配置解析
# - json: JSON数据处理
# - net/http, uri, digest: HTTP客户端和摘要
# - dotenv: 环境变量加载
# - whois: 域名WHOIS查询
# - timeout, date, time: 时间和超时处理
# - concurrent-ruby: 并发处理和Promise
# - prometheus-client: 指标收集和格式化
# - sinatra: Web框架
# - rack, puma: Web服务器
#

# 集中加载所有外部gem依赖
require 'logger'
require 'yaml'
require 'psych'
require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'dotenv'
require 'whois'
require 'timeout'
require 'date'
require 'time'
require 'concurrent'
require 'prometheus/client'
require 'prometheus/client/formats/text'
require 'sinatra/base'
require 'rack'
require 'rack/handler/puma'

# 加载核心模块
require_relative 'domain_monitor/version'

module DomainMonitor
  class Error < StandardError; end

  # 惰性加载子模块
  autoload :Config, 'domain_monitor/config'
  autoload :Logger, 'domain_monitor/logger'
  autoload :NacosClient, 'domain_monitor/nacos_client'
  autoload :WhoisClient, 'domain_monitor/whois_client'
  autoload :Checker, 'domain_monitor/checker'
  autoload :Exporter, 'domain_monitor/exporter'
  autoload :Application, 'domain_monitor/application'

  class << self
    # 条件化加载Nacos支持
    def enable_nacos_support!
      return if defined?(@nacos_enabled)

      @nacos_enabled = true
      # Nacos相关依赖已经在顶部加载
    end

    # 条件化加载Prometheus支持
    def enable_prometheus_support!
      return if defined?(@prometheus_enabled)

      @prometheus_enabled = true
      # Prometheus相关依赖已经在顶部加载
    end

    # 检查功能是否启用
    def nacos_enabled?
      defined?(@nacos_enabled) && @nacos_enabled
    end

    def prometheus_enabled?
      defined?(@prometheus_enabled) && @prometheus_enabled
    end
  end
end
