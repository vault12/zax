# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/body_error'

# --- Request BODY checks ---
module Helpers
  module RequestBodyHelper
    include Errors

    protected
    # check that every request body has the expected number of lines
    def _check_body(body)
      if body.nil? or body.empty?
        fail BodyError.new self, msg: 'No request body', body:nil, lines:0
      end
      nl = body.include?("\r\n") ? "\r\n" : "\n"
      return body.split nl
    end

    def _check_body_lines(body, numoflines, m)
      lines = _check_body body
      unless lines and lines.count == numoflines
        fail BodyError.new self,
          msg: "#{m}: wrong number of lines in BODY",
          body: dumpHex(body),
          lines: lines.count
      end
      return lines
    end
  end
end
