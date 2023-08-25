# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class SessionController < ApplicationController
  include Helpers::TransactionHelper

  before_action :preamble

  # POST /start_session - start handshake
  def start_session_token
    reportCommonErrors("start_session_token error ") do
      # ready only the number of bytes we expect
      @body = request.body.read SESSION_START_BODY

      # we expect 1 line to be start session
      lines = _check_body_lines @body, 1, 'start session'

      # check that the client token is valid
      @client_token = _check_client_token lines[0]

      # lets make the relay token to initiate handshake
      @relay_token  = make_relay_token

      # save both tokens to redis
      cache_tokens

      diff = get_diff(false)

      # Send back our token in a base64 response body
      render plain: "#{@relay_token.to_b64}\r\n#{diff}"

      adjust_difficulty
    end
  end

  # POST /verify_session - verify started handshake
  def verify_session_token
    reportCommonErrors("verify_session_token error ") do
      # read only the bytes we expect for verification
      @body = request.body.read SESSION_VERIFY_BODY

      # original token and signature in 2 lines
      lines = _check_body_lines @body, 2, 'verify session'

      # check that client token line is valid
      _check_client_token lines[0]

      # decode and check both lines
      decode = decode_lines lines

      # check handshake or throw error
      # returns client_token and its h2() from cache
      ct, h2_ct = verify_handshake(decode)

      # signature is valid, lets make temp keys
      session_key = make_session_key h2_ct

      # resond with relay temp key for this session
      # masked by client token
      render plain: "#{session_key.public_key.to_bytes.to_b64}"

      adjust_difficulty
    end
  end

  # Missing routes, mostly triggered by spammers
  def missing_route
    logger.warn "#{SPAM} Spammers scan for: #{request.path}"
    head :service_unavailable # Let's pretend we are dead
  end

  # === Private helper functions ===
  private

  def preamble # runs before every response
    expires_now  # never cache
  end

  # Use NaCl service to generate random 32 bytes token
  def make_relay_token
    relay_token = RbNaCl::Random.random_bytes TOKEN_LEN

    # Sanity check server-side RNG
    if !relay_token || relay_token.length != TOKEN_LEN
      fail SeverRandomError.new
    end
    relay_token
  end

  # Save to cache @client_token and @relay_token
  # This pair will identify unique handshake until the session is ready
  def cache_tokens
    h2_client_token = h2 @client_token
    Rails.cache.write "client_token_#{h2_client_token}",
      @client_token,
      expires_in: Rails.configuration.x.relay.token_timeout

    Rails.cache.write "relay_token_#{h2_client_token}",
      @relay_token,
      expires_in: Rails.configuration.x.relay.token_timeout
  end

  # decode body lines from base64 and return the decoded array
  def decode_lines(lines)
    lines.map do |l|
      if l.length == TOKEN_B64
        l.from_b64
      else
        fail ReportError.new self,
          msg:"verify_session lines wrong size, expecting #{TOKEN_B64}"
      end
    end
  end

  # h₂(client_token) becomes the handhshake storage tag in redis
  # if we dont find client_token itself at that storage key
  # it means there was no handshake or it is expired
  def load_cached_tokens(h2_ct)
    ct = Rails.cache.read "client_token_#{h2_ct}"
    if ct.nil? || ct.length != TOKEN_LEN
      fail ClientTokenError.new self,
        client_token: dumpHex(ct),
        msg: "session controller: client token not registered/wrong size, expecting #{TOKEN_LEN}b"
    end

    rt = Rails.cache.read "relay_token_#{h2_ct}"
    if rt.nil? || rt.length != TOKEN_LEN
      fail RelayTokenError.new self,
        rt: dumpHex(rt),
        msg: "session controller: relay token not registered/wrong size, expecting #{TOKEN_LEN}b"
    end
    [ct,rt]
  end

  # For simple 0 diffculty handshake simply verifies
  # that the client sent h₂(client_token,relay_token).
  # For higher difficulty, verify that the nonce sent by
  # client makes h₂(client_token, relay_token, nonce)
  # to have difficulty num of leading zero bits.
  def verify_handshake(lines)
    h2_client_token, h2_client_sign = lines
    ct, rt = load_cached_tokens(h2_client_token)
    unless h2_client_token.eql? h2(ct)
      fail ClientTokenError.new self,
        client_token: dumpHex(ct),
        msg: 'handshake mismatch: wrong client token'
    end

    # With difficulty throttling we keep a short window for
    # older nonces to validate using older diff setting
    # Window closes when ZAX_TEMP_DIFF expires in redis
    diff = get_diff
    unless static_diff?
      diff2 = get_diff(true)  # Old value if present
      if diff != diff2 # There was a recent change
        if diff == 0 or diff2 == 0 # Special case of changing to/from 0 diff
          correct_sign = h2(ct + rt) # Check if client uses 0 diff algorithm
          diff = 0 if h2_client_sign.eql? correct_sign
        else
          # Use easier one to confirm
          diff = [diff,diff2].min
        end
      end
    end

    if diff == 0
      correct_sign = h2(ct + rt)
      unless h2_client_sign.eql? correct_sign
        fail ClientTokenError.new self,
          client_token: dumpHex(ct),
          msg: 'handshake: wrong hash for 0 difficulty'
      end
    else
      nonce = h2_client_sign
      hash = h2(ct + rt + nonce).bytes
      unless array_zero_bits?(hash, diff)
        fail ClientTokenError.new self,
          client_token: dumpHex(ct),
          msg: "handshake: wrong nonce for difficulty #{diff}"
      end
    end
    return [ct, h2_client_token]
  end

  # Once the client passes handshake verification, we generate and cache the
  # session keys.
  def make_session_key(h2_client_token)
    # establish session keys
    session_key = RbNaCl::PrivateKey.generate

    # report errors with keys if any
    if session_key.nil? || session_key.public_key.to_bytes.length != KEY_LEN
      fail SeverKeyError.new(self, msg: 'New session key: generation failed or too short')
    end

    # store session key on the h₂(client_token) tag in redis
    Rails.cache.write(
      "session_key_#{h2_client_token}",
      session_key,
      expires_in: Rails.configuration.x.relay.session_timeout )
    session_key
  end

  def adjust_difficulty
    return if static_diff? # Throttling disabled if period not set
    period = Rails.configuration.x.relay.period
    rds.incr "ZAX_session_counter_#{ DateTime.now.minute / period }"
    unless rds.exists? ZAX_DIFF_JOB_UP
      # begining of next period
      job_time = start_diff_period(period, 1)
      ttl = job_time.to_i - DateTime.now.to_i
      rds.set ZAX_DIFF_JOB_UP, 1, **{ ex: ttl }
      DiffAdjustJob.set(wait_until: job_time).perform_later()

      # If traffic spike is over reset to normal difficulty
      cleanup_time = start_diff_period(period, ZAX_DIFF_LENGTH)
      DiffAdjustJob.set(wait_until: cleanup_time).perform_later()
    end
  end
end
