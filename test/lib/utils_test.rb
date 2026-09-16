# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'utils'

class UtilsTest < ActiveSupport::TestCase
  include Utils

  # toHex must zero-pad each byte, otherwise low bytes lose a digit
  # and distinct byte strings collapse to the same/ambiguous fragment.
  test 'toHex zero-pads every byte' do
    assert_equal '000102ff', toHex([0x00, 0x01, 0x02, 0xff].pack('C*'))
    # Distinct inputs that the old unpadded toHex would have collided:
    # [0x12] -> "12" and [0x01,0x02] -> "12"
    assert_not_equal toHex([0x12].pack('C*')), toHex([0x01, 0x02].pack('C*'))
    # length is always 2 chars per byte
    assert_equal 64, toHex(rand_bytes(32)).length
  end

  # dumpHex must not return nil for fragments shorter than 8 hex chars
  test 'dumpHex handles short values without returning nil' do
    assert_equal 'nil', dumpHex(nil)
    # 2 bytes => 4 hex chars, shorter than the 8-char tail slice
    assert_equal '0102', dumpHex([0x01, 0x02].pack('C*'))
    # long value: last 8 hex chars
    assert_equal 8, dumpHex(rand_bytes(32)).length
    # full form returns the whole padded hex
    assert_equal 64, dumpHex(rand_bytes(32), true).length
  end

  # log_safe neutralizes control/escape bytes in client text (so a
  # crafted request path can't forge log lines or corrupt a tailing terminal)
  # while keeping ordinary text readable and bounding length.
  test 'log_safe escapes control bytes, stays readable, and truncates' do
    # benign input stays readable (just quoted)
    assert_equal '"/wp-login.php"', log_safe('/wp-login.php')

    # CRLF cannot inject a raw newline (no forged log line)
    crlf = log_safe("/x\r\nSpammers scan for: FORGED")
    refute_includes crlf, "\n"
    refute_includes crlf, "\r"
    assert_includes crlf, '\\r\\n' # shown as a literal escape instead

    # ANSI/terminal escape byte is neutralized
    refute_includes log_safe("/\e[2Jhax"), "\e"

    # over-length input is bounded and marked
    long = log_safe('/' + 'A' * 500, 128)
    assert_operator long.bytesize, :<, 200
    assert long.end_with?('...(truncated)')
  end
end
