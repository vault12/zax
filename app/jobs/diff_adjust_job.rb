# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class DiffAdjustJob < ApplicationJob
  include Helpers::TransactionHelper
  queue_as :default

  def perform(*args)
    # Omiting period or setting it to 0 signals no dynamic difficulty adjustments
    return if static_diff?

    # Immidiately open lock for the next job to be scheduled if needed
    rds.del ZAX_DIFF_JOB_UP

    t = DateTime.now
    period = Rails.configuration.x.relay.period
    # Did we just run a job for this period?
    period_marker = "ZAX_difficulty_last_job_#{ t.minute / period }"
    return if rds.exists? period_marker
    rds.set period_marker, 1, **{ ex: period * 60 }

    min_diff = $redis.get(ZAX_ORIGINAL_DIFF).to_i
    diff = get_diff

    factor = Rails.configuration.x.relay.overload_factor || 2.0
    min_requests = Rails.configuration.x.relay.min_requests || 100
    diff_increase = Rails.configuration.x.relay.diff_increase || 1

    next_block  = roundup_block(t, period, 1)

    # clean up next block for recording on next cycle
    rds.del "ZAX_session_counter_#{next_block}"

    count = timeblock_counter roundup_block(t, period, -1)
    count += timeblock_counter(roundup_block(t, period, -2))/2 # 50% of 2 periods ago
    count += timeblock_counter(roundup_block(t, period, -3))/3 # 33% of 3 periods ago

    # increasing requests, increase diff
    if count > min_requests
      diff = min_diff + (diff_increase*Math.log(count/min_requests,factor)+0.5).to_i

    # decreasing requests, decrease diff
    elsif diff > min_diff
      # Requests at minimum level, reset to default diff
      if count <= min_requests
        diff = min_diff
      # Factor diff reduction by reduced load
      elsif count > min_requests
        diff = min_diff + (diff_increase*Math.log(count/min_requests,factor)+0.5).to_i
        diff = min_diff if diff < min_diff
      end
    end

    arr = diff > get_diff ? UP_ARR : DOWN_ARR
    logger.info "#{INFO} Difficulty throttling: #{arr}  #{RED}#{diff}#{ENDCLR} #{ENDCLR}"

    set_diff(diff)
  end

  def roundup_block(time,period,count)
    (time + (count*period).minutes - (time.minute % period).minutes ).minute / period
  end

  def timeblock_counter(block)
    v = $redis.get "ZAX_session_counter_#{block}"
    v ? v.to_i : 0
  end

end
