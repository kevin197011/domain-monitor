# frozen_string_literal: true

require 'logger'

module DomainMonitor
  # Logger management class
  # Provides unified logging functionality across the application
  class Logger
    class << self
      def create(component)
        logger = ::Logger.new($stdout)
        logger.formatter = proc do |severity, time, progname, msg|
          "[#{time.strftime('%Y-%m-%d %H:%M:%S %z')}] #{severity} #{progname}: #{msg}\n"
        end
        logger.progname = component
        logger.level = current_level
        register(logger)
        logger
      end

      def update_all_level(level)
        @current_level = level
        loggers.each { |logger| logger.level = level }
      end

      private

      def loggers
        @loggers ||= []
      end

      def register(logger)
        loggers << logger
      end

      def current_level
        return @current_level if defined?(@current_level)

        level = Config.instance.log_level || 'info'
        @current_level = ::Logger.const_get(level.upcase)
      rescue NameError
        @current_level = ::Logger::INFO
      end
    end
  end
end
