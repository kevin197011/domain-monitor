# frozen_string_literal: true

require 'logger'

module DomainMonitor
  # Custom logger formatter for consistent log format
  class LoggerFormatter < Logger::Formatter
    def call(severity, time, progname, msg)
      "[#{time.strftime('%Y-%m-%d %H:%M:%S %z')}] #{severity} #{progname}: #{msg}\n"
    end
  end

  # Logger factory for creating consistent loggers
  class LoggerFactory
    LOG_LEVELS = {
      'debug' => Logger::DEBUG,
      'info' => Logger::INFO,
      'warn' => Logger::WARN,
      'error' => Logger::ERROR,
      'fatal' => Logger::FATAL
    }.freeze

    class << self
      def create_logger(component, level = 'info')
        logger = Logger.new($stdout)
        logger.formatter = LoggerFormatter.new
        logger.progname = component
        logger.level = LOG_LEVELS[level.to_s.downcase] || Logger::INFO
        logger
      end
    end
  end
end
