module KeyParams
  # Well known names
  TOKEN     = "X_REQUEST_TOKEN"
  TOKEN_LEN = 32
  TOKEN_B64 = 44

  HPK       = "X_HPK"
  HPK_LEN   = 32

  NONCE_LEN = 24
  NONCE_B64 = 32

  KEY_LEN   = 32
  KEY_B64   = 44

  MAX_COMMAND_BODY = 10*1024 # 10kb
  MAX_ITEMS        = 100

  SESSION_START_BODY  = TOKEN_B64
  SESSION_VERIFY_BODY = TOKEN_B64 + 2 + TOKEN_B64
  PROVE_BODY          = MAX_COMMAND_BODY
  COMMAND_BODY        = MAX_COMMAND_BODY

  # Log file prefix codes.
  #
  # First char of log lines show visual icon of
  # that line importance.

  # Low level info, can be ignored
  # 🔩 - Nuts and bolts
  INFO      = "\xF0\x9F\x94\xA9 "

  # Low level info, can be ignored, minor positve on the protocol path
  # 🔑 - Secure keys, good path
  INFO_GOOD = "\xF0\x9F\x94\x91 "

  # Low level info, can be ignored, minor deviation from the protocol path
  # 🔻 - Downward tick
  INFO_NEG  = "\xF0\x9F\x94\xBB "

  # A noteworthy event, a non-breaking deviation from the protocol path
  # 🚩 - A red flag
  WARN      = "\xF0\x9F\x9A\xA9 " #"\xE2\x80\xA0"

  # important, breaking event, must be investigated.
  # ❗️ - A red error
  ERROR     = "\xE2\x9D\x97\xEF\xB8\x8F"

  # Exception text
  # ☢ - A toxic trace
  EXPT      = "\xE2\x98\xA2"
end
