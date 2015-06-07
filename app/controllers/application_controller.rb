require "key_params"

class ApplicationController < ActionController::API
  include ResponseHelper
  before_filter :allow_origin

  public
  def allow_crossdomain
    headers['Access-Control-Allow-Methods']   = 'POST, PUT, DELETE, GET, OPTIONS'
    headers['Access-Control-Request-Method']  = '*'
    headers['Access-Control-Allow-Headers']   = "#{TOKEN},#{HPK}"

    # Eliminate CORS pre-flight requests as much as possible
    expires_in 1.week, :public => true
  end

  def allow_origin
    headers['Access-Control-Allow-Origin']    = '*'
    headers['Access-Control-Expose-Headers']  = "X-Error-Details"
  end

  protected
  def _check_body(body)
    raise "No request body" if body.nil? or body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    return body.split nl
  end

end