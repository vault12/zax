require 'test_helper'

class ProofControllerTest < ActionController::TestCase
  test "prove :hpk guard" do
    head :prove_hpk
    _fail_response :precondition_failed # no header

    rid = RbNaCl::Random.random_bytes 32
    @request.headers["HTTP_REQUEST_TOKEN"] = Base64.strict_encode64 rid
    head :prove_hpk
    _fail_response :precondition_failed # unconfirmed token

    # fake token 
    Rails.cache.fetch(rid, expires_in: 1) do
      RbNaCl::Random.random_bytes 32
    end
    head :prove_hpk
    _fail_response :precondition_failed # token alone not enough

  end
end