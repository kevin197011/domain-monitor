# frozen_string_literal: true

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

      def instance
        @instance ||= create('DomainMonitor')
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
        return @current_level if defined?(@current_level) && @current_level

        level_name = 'info'
        begin
          level_name = Config.log_level if defined?(Config) && Config.respond_to?(:log_level)
        rescue StandardError
          # 如果Config还未初始化，使用默认值
        end

        @current_level = ::Logger.const_get(level_name.upcase)
      rescue NameError
        @current_level = ::Logger::INFO
      end
    end
  end
end
