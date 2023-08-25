# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class DiffAdjustJobTest < ActiveJob::TestCase
  include Helpers::TransactionHelper

  ZAXs = 'ZAX_session_counter_'

  def setup
    # Avoid tests on minute edge: our setup may split over 2 blocks
    sleep(2.5) if DateTime.now.second > 57

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
    sleep(2.5) if DateTime.now.second > 57 # Avoid tests on minute edge
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
    sleep(2.5) if DateTime.now.second > 57 # Avoid tests on minute edge
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
    sleep(2.5) if DateTime.now.second > 57 # Avoid tests on minute edge
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
    sleep(2.5) if DateTime.now.second > 57 # Avoid tests on minute edge
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

  def roundup_block(time,period,count)
    (time + (count*period).minutes - (time.minute % period).minutes ).minute / period
  end

end
