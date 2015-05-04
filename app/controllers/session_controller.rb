require "base64"

class SessionController < ApplicationController

  def new_session_token
    rid = Base64.decode64 request.headers["HTTP_REQUEST_TOKEN"]
    token = RbNaCl::Random.random_bytes 32
    Rails.cache.fetch(rid, expires_in: 5.minutes) { token }
    render text: Base64.encode64(token)
  end

  def verify_session_token
    rid = Base64.decode64 request.headers["HTTP_REQUEST_TOKEN"]
    render text: Base64.encode64(Rails.cache.fetch rid)
  end
end