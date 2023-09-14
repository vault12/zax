# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class ApplicationController < ActionController::API
  include ResponseHelper
  before_action :check_restart_window
  before_action :allow_origin

  public

  def check_restart_window
    rw = Rails.configuration.x.relay.restart_window
    return unless rw
    counter = Rails.configuration.x.relay.restart_window_max_seconds || 10
    while rw.call and counter > 0
      sleep 1
      counter -= 1
    end
  end

  def allow_origin
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Headers'] = 'Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Session-ID,Content-Type,Content-Range,Content-Disposition';
    headers['Cache-Control'] = "no-transform," + ( headers['Cache-Control'] || "")
  end

  protected

  def add_error_context(l)
    l =  "#{RED}#{l}#{ENDCLR}"
    l += " #{CMD}#{GREEN}#{@cmd}#{ENDCLR}" if @cmd
    l += " hpk: #{MAGENTA}'#{dumpHex @hpk}'#{ENDCLR}" if @hpk
    return l
  end

  def reportCommonErrors(context_label)
    yield
    rescue RbNaCl::CryptoError => e
      logger.error add_error_context(context_label)
      ZaxError.new(self).NaCl_error e
    rescue Redis::CommandError => e
      logger.error add_error_context(context_label)
      TransactionError.new(self,
        { hpk: @hpk,
          msg: "#{RED}Redis error:#{ENDCLR} #{e}"
        }).http_fail
    rescue ZaxError => e
      logger.error add_error_context(context_label)
      e.http_fail
    rescue ArgumentError => e
      ReportError.new(self).report add_error_context(context_label), e
    rescue => e
      ZaxError.new(self).severe_error add_error_context(context_label),e
  end
end
