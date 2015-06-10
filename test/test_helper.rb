ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'response_helper'

class ActiveSupport::TestCase
  include ResponseHelper

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
end

# Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
#
# fixtures :all