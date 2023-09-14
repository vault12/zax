# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'utils'
module Errors

  # Root class for our internal ZAX errors
  #
  # Relay internal errors will inherit from ZaxError.
  # Catch block handles 3 types of errors:
  # - RbNaCl::CryptoError for encryption
  # - ZaxError of relay own error conditions
  # - general errors from other libraries
  #
  # All known relay errors related to the protocol will return :bad_request.
  # No details of crypto errors are given to the client besides formatting
  # errors of a client request. Error details are logged
  # in the relay logs at :warning or :error levels depending on severity.
  #
  # :internal_server_error - a grave internal error that the
  # relay can not recover from on its own, usually related to
  # external services (such as RNG). The system administrator should
  # investigate these errors, they are always logged at ERROR level.
  # Clients get a response with :internal_server_error code so that
  # they may avoid using given relay for the time being.

  class ZaxError < StandardError
    include Utils

    def initialize(ctrl, data = nil)
      @controller = ctrl
      @data = data
      @response_code = :bad_request
    end

    def http_fail
      # No information about the relay state is sent back to the client for known error conditions
      if @controller and @controller.class < ApplicationController
        @controller.expires_now
        xerr = @response_code != :internal_server_error ? 'Your request can not be completed.' : 'Something is wrong with this relay. Try again later.'
        @controller.head @response_code, x_error_details: xerr
      end
      @err_msg = ( @data and @data.is_a?(Hash) and @data[:msg] ) ? @data[:msg] : ''
      warn "#{INFO_NEG} #{@err_msg}"

      # Discard any set redis WATCH
      if Thread.current[:redis]
        begin
          rds = Thread.current[:redis]
          rds.discard if rds.connected?
        rescue
          # Ignore any redis issues since we already
          # dealing with some error
        end
      end
    end

    # Used when the relay's internal integrity is in doubt
    def severe_error(note ="", excpt)
      if @controller and @controller.class < ApplicationController
        @controller.expires_now
        @controller.head :internal_server_error,
          x_error_details: 'Something is wrong with this relay. Try again later.'
      end
      _log_exception ERROR,note,excpt
    end

    # This is used to log general non-ZAX exceptions
    def report(note, excpt)
      # handle non-ZAX errors, such as encoding, etc.
      @controller.expires_now
      @controller.head @response_code,
        x_error_details: 'Your request can not be completed.'
      _log_exception WARN,note,excpt
    end

    # This is used to log RbNaCl errors
    def NaCl_error(e)
      e1 = e.is_a?(RbNaCl::BadAuthenticatorError) ? 'The authenticator was forged or otherwise corrupt' : ''
      e2 = e.is_a?(RbNaCl::BadSignatureError) ? 'The signature was forged or otherwise corrupt' : ''
      error "#{ERROR} Decryption error for packet:\n"\
        "#{e1}#{e2} "\
        "#{@controller.body}"
      _log_exception ERROR, "Stack trace", e

      @controller.head @response_code,
        x_error_details: 'Your request can not be completed.'
    end

    # === Exception loging functions ===
    def _log_exception(icon, note, excpt)
      warn "#{icon} #{note}:\n#{EXPT} \xE2\x94\x8C#{excpt} \xE2\x94\x90"
      warn excpt.backtrace[0..7].reduce("") { |s,x|
        s += "#{EXPT} \xE2\x94\x9C#{x}\n" } +
      "#{EXPT} \xE2\x94\x94#{BAR*25}\xE2\x94\x98"
    end

    def log_message(m)
      #  "#{m}:\n#{dumpHex @data}:\n#{EXPT} #{self}\n---"
      "#{m}"
    end

    def info(m)
      Rails.logger.info log_message m
      # @controller.logger.info log_message m
    end

    def warn(m)
      Rails.logger.warn log_message m
      # @controller.logger.warn log_message m
    end

    def error(m)
      Rails.logger.error log_message m
    end
  end
end
