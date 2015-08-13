ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'response_helper'

class ActiveSupport::TestCase
  include ResponseHelper

  def redisc
    Redis.current
  end

  def redisup
    begin
       redisc.ping
    rescue Errno::ECONNREFUSED => e
       puts "Error: Redis server unavailable. Shutting down..."
       exit 1
    end
  end

  def _fail_response(status)
    assert_response status
    assert_includes(response.headers,"X-Error-Details")
    assert_empty response.body
  end

  def _success_response
    assert_response :success
    assert_not_includes(response.headers,"X-Error-Details")
    assert_not_empty response.body
  end

  def _raw_post(action, params, *lines)
    @request.env['RAW_POST_DATA'] = lines.reduce("") { |s,v| s+="#{b64enc v}\n" }
    post action,params
  end

  def _corrupt_str(str)
    corrupt = str.clone
    corrupt[0] = [corrupt[0].ord+1].pack("C")
    corrupt
  end

  def _test_random_pair
    hpk = Random.new.rand(0..2)
    hpkto = Random.new.rand(0..2)
    if hpk == hpkto
      return true, []
    else
      return false, [hpk,hpkto]
    end
  end

  # get an array with 2 different values
  def _get_random_pair
    values = []
    begin
      values = _test_random_pair
    end while values[0]
    values[1]
  end

end
