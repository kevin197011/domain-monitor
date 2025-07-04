# frozen_string_literal: true

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
require 'whois-parser'
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
end
