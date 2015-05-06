ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

def logger
  Rails.logger
end

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #### fixtures :all

  # Add more helper methods to be used by all tests here...

  def _fail_response(status)
    assert_response status 
    assert_includes(response.headers,"Error-Details")
    assert_empty response.body
  end

  def _success_response
    assert_response :success
    assert_not_includes(response.headers,"Error-Details")
    assert_not_empty response.body
  end
end