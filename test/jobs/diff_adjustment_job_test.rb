# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class DiffAdjustJobTest < ActiveJob::TestCase
  include Helpers::TransactionHelper

  ZAXs = 'ZAX_session_counter_'

  def setup
    # Freeze time: the block-index math is minute-derived, so a real minute tick between setup and the job run 
    # could split a test across two blocks. Frozen time makes setup/run/teardown agree on one instant - deterministic. 
    travel_to Time.utc(1997, 10, 10, 21, 6, 1)

    @save_min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    @save_diff = get_diff

    set_diff 4
    # minimal difficulty min_diff
    $redis.set ZAX_ORIGINAL_DIFF, 4

    # if we get more then ...
    Rails.configuration.x.relay.min_requests = 10
    # ... per period of ...
    Rails.configuration.x.relay.period = 2
    # ... minutes, and number of request grows by factor of
    Rails.configuration.x.relay.overload_factor = 2
    # ... comparing to min_request we will increase difficulty by...
    Rails.configuration.x.relay.diff_increase = 3
    # ... bit longer, per each factor, 0-leading string in session handshake

    clear_counters()
  end

  def teardown
    clear_counters()
    $redis.set ZAX_ORIGINAL_DIFF, @save_min_diff
    set_diff @save_diff
    rds.del ZAX_CUR_DIFF
  end

  def clear_counters
    period = Rails.configuration.x.relay.period
    for i in (-4..0)
      rds.del "#{ZAXs}#{ roundup_block(DateTime.now,period,i) }"
    end
    rds.del "ZAX_difficulty_last_job_#{ DateTime.now.minute / period }"
  end

  test "difficulty stable" do
    t = DateTime.now

    period = Rails.configuration.x.relay.period
    diff = get_diff

    min_requests = Rails.configuration.x.relay.min_requests
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", (min_requests-1)

    reqs = rds.get("#{ZAXs}#{ roundup_block(t,period,-1) }").to_i
    assert_equal min_requests-1, reqs

    DiffAdjustJob.perform_now

    # Difficulty not changed
    assert_equal diff, get_diff
  end

  test "difficulty increasing" do
    t = DateTime.now

    period = Rails.configuration.x.relay.period

    min_requests = Rails.configuration.x.relay.min_requests
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", 2*min_requests

    reqs = rds.get("#{ZAXs}#{ roundup_block(t,period,-1) }").to_i
    assert_equal 2*min_requests, reqs

    DiffAdjustJob.perform_now

    # # Difficulty increase by one factor from min, one increase of diff_increase
    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    assert_equal min_diff + 3, get_diff
  end

  test "difficulty decreasing" do
    t = DateTime.now

    period = Rails.configuration.x.relay.period
    diff = set_diff 16

    min_requests = Rails.configuration.x.relay.min_requests
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", 4*min_requests

    reqs = rds.get("#{ZAXs}#{ roundup_block(t,period,-1) }").to_i
    assert_equal 4 * min_requests, reqs

    DiffAdjustJob.perform_now

    # Difficulty decrease by two factors, two decrease of diff_increase
    assert_equal 10, get_diff

    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    assert_equal min_diff + 2*3, get_diff
  end

  test "difficulty never goes under minimum" do
    t = DateTime.now

    period = Rails.configuration.x.relay.period
    set_diff 6

    min_requests = Rails.configuration.x.relay.min_requests

    # zero requests
    rds.del "#{ZAXs}#{ roundup_block(t,period,-1) }"
    reqs = rds.get("#{ZAXs}#{ roundup_block(t,period,-1) }").to_i
    assert_equal 0, reqs

    DiffAdjustJob.perform_now

    # Difficulty decrease by 4 factors, reset to minimal diff
    assert_equal 4, get_diff
  end

  # integer division kept the increase at zero until 2x
  # min_requests. 1.5x load must already raise difficulty:
  # (3 * log2(1.5) + 0.5).to_i == 2
  test "difficulty rises below 2x min_requests" do
    t = DateTime.now

    period = Rails.configuration.x.relay.period
    min_requests = Rails.configuration.x.relay.min_requests
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", (1.5 * min_requests).to_i

    DiffAdjustJob.perform_now

    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    assert_equal min_diff + 2, get_diff
  end

  # block indexes are cyclic within the hour, so with period=15 the
  # +1 (cleanup) and -3 (1/3 term) indexes alias. Cleanup-before-read
  # permanently zeroed the 1/3 term; the job must read before deleting.
  test "one-third term survives next-block cleanup when indexes alias" do
    t = DateTime.now # frozen (see setup): minute 5 => mid-period for period 15
    Rails.configuration.x.relay.period = 15
    min_requests = Rails.configuration.x.relay.min_requests

    (-3..1).each { |i| rds.del "#{ZAXs}#{ roundup_block(t,15,i) }" }
    rds.del "ZAX_difficulty_last_job_#{ t.minute / 15 }"

    # -1 alone is exactly min_requests (no increase); only the 1/3 of the
    # aliased -3 block pushes the count to 2x => +diff_increase
    rds.set "#{ZAXs}#{ roundup_block(t,15,-1) }", min_requests
    rds.set "#{ZAXs}#{ roundup_block(t,15,-3) }", 3 * min_requests

    DiffAdjustJob.perform_now

    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    assert_equal min_diff + 3, get_diff
  ensure
    t = DateTime.now
    (-3..1).each { |i| rds.del "#{ZAXs}#{ roundup_block(t,15,i) }" }
    rds.del "ZAX_difficulty_last_job_#{ t.minute / 15 }"
    Rails.configuration.x.relay.period = 2
  end

  # bad operator config (factor=1 => infinite log, min_requests=0
  # => division by zero) crashed the job every run — it must fall back to
  # safe defaults instead
  test "invalid overload_factor and min_requests do not crash the job" do
    t = DateTime.now
    period = Rails.configuration.x.relay.period
    min_requests = Rails.configuration.x.relay.min_requests
    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i

    # log base 1 => FloatDomainError before the fix; falls back to 2.0
    Rails.configuration.x.relay.overload_factor = 1
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", 2 * min_requests
    DiffAdjustJob.perform_now
    assert_equal min_diff + 3, get_diff

    # min_requests=0 => ZeroDivisionError before the fix; falls back to 100
    clear_counters
    Rails.configuration.x.relay.min_requests = 0
    set_diff min_diff
    rds.set "#{ZAXs}#{ roundup_block(t,period,-1) }", 20 # under the fallback 100
    DiffAdjustJob.perform_now
    assert_equal min_diff, get_diff
  ensure
    Rails.configuration.x.relay.overload_factor = 2
    Rails.configuration.x.relay.min_requests = 10
  end

  def roundup_block(time,period,count)
    (time + (count*period).minutes - (time.minute % period).minutes ).minute / period
  end

end
