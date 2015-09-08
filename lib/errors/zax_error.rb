require 'utils'
module Errors
  # root class for our internal ZAX errors
  class ZAXError < StandardError
    include Utils

    def initialize(ctrl, data = nil)
      @controller = ctrl
      @data = data
    end

    def http_fail
      @controller.expires_now
      @controller.head :bad_request, x_error_details: @data[:msg]
    end

    # Exception loging functions
    def log_message(m)
      #  "#{m}:\n#{dumpHex @data}:\n#{EXPT} #{self}\n---"
      "#{m}\n"
    end

    def info(m)
      @controller.logger.info log_message m
    end

    def warn(m)
      @controller.logger.warn log_message m
    end

    def error(m)
      @controller.logger.error log_message m
    end
  end
end
