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

  MAX_COMMAND_BODY = 100*1024 # 100kb
  MAX_ITEMS        = 100

  # Log file prefix codes.
  # 
  # First char of log lines show visual icon of
  # that line importance. 

  # low level info, can be ignored
  INFO      = "\xF0\x9F\x94\xA9 "

  # low level info, can be ignored, minor positve on the protocol path
  INFO_GOOD = "\xF0\x9F\x94\x91 "

  # low level info, can be ignored, minor deviation from the protocol path
  INFO_NEG  = "\xF0\x9F\x94\xBB "

  # a noteworthy event, a non-breaking deviation from the protocol path
  WARN      = "\xF0\x9F\x9A\xA9 " #"\xE2\x80\xA0"

  # important, breaking event, must be investigated.
  ERROR     = "\xE2\x9D\x97\xEF\xB8\x8F"

  EXPT      = "\xE2\x98\xA2"
end