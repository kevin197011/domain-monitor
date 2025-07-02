# frozen_string_literal: true

require 'sinatra/base'
require 'prometheus/client'
require 'prometheus/client/formats/text'
require 'rack'

module DomainMonitor
  class Exporter < Sinatra::Base
    # Set Puma as server
    set :server, :puma
    # Listen on all interfaces
    set :bind, '0.0.0.0'
    # Set production environment
    set :environment, :production

    def initialize(checker, config = Config.instance)
      super()
      @checker = checker
      @config = config
      @logger = config.create_logger('Exporter')
      setup_metrics
    end

    def self.run_server!(checker, config)
      set :port, config.metrics_port
      app = new(checker, config)

      Thread.new do
        Rack::Handler.default.run(app, Host: '0.0.0.0', Port: config.metrics_port)
      end
    end

    # Health check endpoint
    get '/health' do
      content_type 'application/json'
      '{"status":"up"}'
    end

    # Metrics endpoint
    get '/metrics' do
      content_type 'text/plain; version=0.0.4'
      collect_metrics
      Prometheus::Client::Formats::Text.marshal(@registry)
    end

    private

    def setup_metrics
      @registry = Prometheus::Client.registry

      @expire_days = Prometheus::Client::Gauge.new(
        :domain_expire_days,
        docstring: 'Domain expiration days remaining',
        labels: [:domain]
      )

      @expired = Prometheus::Client::Gauge.new(
        :domain_expired,
        docstring: 'Domain is expired or close to expiry (1: yes, 0: no)',
        labels: [:domain]
      )

      @check_status = Prometheus::Client::Gauge.new(
        :domain_check_status,
        docstring: 'Domain check status (1: success, 0: error)',
        labels: [:domain]
      )

      @registry.register(@expire_days)
      @registry.register(@expired)
      @registry.register(@check_status)
    end

    def collect_metrics
      @checker.results.each do |domain, result|
        update_check_status(domain, result[:check_status])
        update_expire_days(domain, result[:check_status] ? (result[:expire_days] || -1) : -1)
        update_expired_status(domain, result[:check_status] && result[:expired])

        if result[:check_status]
          if result[:expired]
            @logger.warn "Domain #{domain} is expired or close to expiry (#{result[:expire_days]} days remaining)"
          else
            @logger.info "Domain #{domain} is healthy (#{result[:expire_days]} days remaining)"
          end
        else
          @logger.error "Domain #{domain} check failed: #{result[:error]}"
        end
      end
    end

    def update_check_status(domain, status)
      @check_status.set(status ? 1 : 0, labels: { domain: domain })
    end

    def update_expire_days(domain, days)
      @expire_days.set(days, labels: { domain: domain })
    end

    def update_expired_status(domain, expired)
      @expired.set(expired ? 1 : 0, labels: { domain: domain })
    end
  end
end
