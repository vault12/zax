ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require "utils"

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #### fixtures :all
  include Utils

  # Add more helper methods to be used by all tests here...
  def logger
    Rails.logger
  end

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

  def _raw_post(action, params, *lines)
    @request.env['RAW_POST_DATA'] = lines.reduce("") { |s,v| s+="#{b64enc v}\n" }
    post action,params
  end

  def _corrupt_str(str)
    corrupt = str.clone
    corrupt[0] = [corrupt[0].ord+1].pack("C")
    corrupt
  end

  def _client_nonce(tnow = Time.now.to_i)
    nonce = (RbNaCl::Random.random_bytes 24).unpack "C24"

    timestamp = (Math.log(tnow)/Math.log(255)).floor.downto(0).map do
      |i| (tnow / 255**i) % 255
    end
    blank = Array.new(8) { 0 } # zero as 8 byte integer

    # 64 bit timestamp, MSB first
    blank[-timestamp.length,timestamp.length] = timestamp

    # Nonce first 8 bytes are timestamp
    nonce[0,blank.length] = blank
    return nonce.pack("C*")
  end

end