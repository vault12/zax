require 'response_helper'

class ApplicationController < ActionController::API
  include ResponseHelper
  before_filter :allow_origin

  public
  # def allow_crossdomain
  #   headers['Access-Control-Allow-Methods']   = 'POST'
  #   headers['Access-Control-Request-Method']  = '*'

  #   # Eliminate CORS pre-flight requests as much as possible
  #   expires_in 1.week, :public => true
  # end

  def allow_origin
    headers['Access-Control-Allow-Origin']    = '*'
  end
end
