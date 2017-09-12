# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
module KeyParams

  # Well known names
  TOKEN     = 'REQUEST_TOKEN'
  TOKEN_LEN = 32
  TOKEN_B64 = 44

  HPK       = 'X_HPK'
  HPK_LEN   = 32
  HPK_B64   = 44

  NONCE_LEN = 24
  NONCE_B64 = 32

  KEY_LEN   = 32
  KEY_B64   = 44

  OUTER_BOX = 256

  MAX_ITEMS        = 100

  SESSION_START_BODY  = TOKEN_B64
  SESSION_VERIFY_BODY = TOKEN_B64 + 2 + TOKEN_B64
  PROVE_BODY          = TOKEN_B64 + 2 + TOKEN_B64 + 2 +
                        NONCE_B64 + 2 + OUTER_BOX
  COMMAND_BODY_PREAMBLE = TOKEN_B64 + 2 + NONCE_B64 + 2
  MAX_COMMAND_BODY      = 1000 * 1024 # 1Mb command body at most

  # Global redis index of all files currently stored
  ZAX_GLOBAL_FILES  = "ZAX_global_files"
  STORAGE_PREFIX    = "file_storage_"

  # Difficulty throttling
  ZAX_ORIGINAL_DIFF = "ZAX_original_difficulty"
  ZAX_CUR_DIFF      = "ZAX_current_difficulty"
  ZAX_TEMP_DIFF     = "ZAX_temp_difficulty"
  ZAX_DIFF_JOB_UP   = "ZAX_difficulty_adjust_job"
  ZAX_DIFF_LENGTH   = 4 # Number of time periods increased diff lasts

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

  CMD = "\xE2\x8C\x98 " # ⌘

  # Low level info, can be ignored, minor deviation from the protocol path
  # 🔻 - Downward tick
  INFO_NEG  = "\xF0\x9F\x94\xBB "

  # A noteworthy event, a non-breaking deviation from the protocol path
  # 🚩 - A red flag
  WARN      = "\xF0\x9F\x9A\xA9 " # "\xE2\x80\xA0"

  # important, breaking event, must be investigated.
  # ❗️ - A red error
  ERROR     = "\xE2\x9D\x97\xEF\xB8\x8F"

  # Exception text
  # ☢ - A toxic trace
  EXPT      = "\xE2\x98\xA2"

  # ⬆️
  UP_ARR = "\xE2\xAC\x86\xEF\xB8\x8F"
  # ⬇️
  DOWN_ARR = "\xE2\xAC\x87\xEF\xB8\x8F"

  # 🐖
  SPAM = "\xF0\x9F\x90\x96 "

  BAR       = "\xE2\x94\x80"

  # Colors
  RED = "\x1B[1;31m"
  GREEN = "\x1B[1;32m"
  BLUE = "\x1B[1;34m"
  MAGENTA = "\x1B[1;35m"
  WHITE = "\x1B[1;37m"
  ENDCLR = "\x1B[0m"

end
