# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class ApplicationController < ActionController::API
  include ResponseHelper
  before_filter :allow_origin

  public

  def allow_origin
    headers['Access-Control-Allow-Origin'] = '*'
  end
end
