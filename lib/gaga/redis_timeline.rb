class RedisTimeline
  attr_accessor :tl, :tlset, :config

  def initialize(redis, config)
    @redis = redis
    @config = config
    @name = @config['twittername']
    @tweet_limit = 10

    # bucket size for rate limiting
    # try 60s for 1min
    # 3600 for 1hr (eg, 100 reads/hr)
    @bucket = 3600
    @global_rate_limit = 100 # per bucket, in this case 100/1s

    @timeline_url = "https://api.twitter.com/1/statuses/user_timeline.json"
    @timeline_url = @timeline_url + "?screen_name=#{@name}"
    @timeline_url = @timeline_url + "&count=#{@tweet_limit}"

    @keys = {
      :update => "rtl:::#{@name}:::last_update",
      :timeline => "rtl:::#{@name}:::timeline",
      :global_updates => "rtl:::global:::updates",
      :reads => "rtl:::#{@name}:::reads:::",
      :global_read_limit => "rtl:::global:::read_limitupdate:::"
    }
    @tl = load_timeline
    @tlset = 1 if @tl != nil
    @tlset = 0 if @tl == nil
  end

  def get_tl
    @tl
  end

  private
  def get_tv_bucket(now, b, prefix)
    tv = now
    tv_bucket = (tv/b) * b
    $log.debug("tv_b(0)#{prefix}: tv => #{tv}, tv_bucket => #{tv_bucket}")
    tv_bucket
  end

  def load_timeline
    # first, see if there is a version in redis, this is default return value
    # then look at current time bucket vs time bucket of curent timeline
    # if within the bucket, return from redis, otherwise fetch
    # if fetch fails, just return cached value

    # if the cached in redis tl's bucket is equal to the current bucket, then return cached result
    # if not, read the timeline and return that. if read fails, keep cached result
    now = Time.now.tv_sec
    now_bucket = get_tv_bucket(now, @bucket, 'now')
    tl_raw = @redis.get(@keys[:timeline])
    if tl_raw != nil
      tl = JSON.parse(tl_raw)
      tl_bucket = get_tv_bucket(tl['ts'], @bucket, 'tl')
      # on cache hit simply return tl
      #$log.debug("ltl(0): hit #{tl.pretty_inspect}") if now_bucket == tl_bucket
      $log.debug("ltl(0): hit") if now_bucket == tl_bucket
      return tl if now_bucket == tl_bucket
    else
      tl = {'ts' => now}
      tl[:results] = JSON.parse(@@default_results)
    end

    # other wise, schedule a read, BUT only if there is no read already outstanding for this key this 1s
    reads_key = "#{@keys[:reads]}#{now}"
    outstanding = @redis.incrby reads_key, 1
    #outstanding = 1
    if outstanding == 1
      # schedule a read and keep key around for ~2s to better debug
      $log.debug("ltl(1): scheduling #{reads_key}")

      # check global rate limit
      rate_limit_key = "#{@keys[:global_read_limit]}#{now_bucket}"
      rate_limit = @redis.incrby rate_limit_key, 1
      @redis.expire(rate_limit_key, @bucket + (@bucket/2)) if rate_limit == 1
      if rate_limit < @global_rate_limit

        # we are under the rate limit and need to do a read, so read away
        httpclient = HTTPClient.new()
        response = httpclient.get @timeline_url
        $log.info("ltl(2): under_limit #{response.status}, #{@timeline_url}, #{response.pretty_inspect}")
        if response.status == 200
          tl = {'ts' => now}
          tl[:results] = JSON.parse(response.body)
          @redis.set(@keys[:timeline], tl.to_json)
          $log.info("ltl(2a): #{response.status} real_response, saved")
        end
        if response.status == 400
          tl = {'ts' => now}
          tl[:results] = JSON.parse(@@default_results)
          @redis.set(@keys[:timeline], tl.to_json)
          $log.info("ltl(2b): #{response.status} default_response, saved")
        end
      else
        $log.debug("ltl(2c): rate_limit exceeded #{rate_limit}, #{reads_key}")
      end
    else
      # schedule a read and keep key around for ~10s to better debug
      $log.debug("ltl(2): read_cache - #{outstanding} for #{reads_key}")
    end
  end
  @@default_results = "[{\"created_at\":\"Wed Jul 25 06:20:14 +0000 2012\",\"id\":228011759863214080,\"id_str\":\"228011759863214080\",\"text\":\"u with me?\",\"source\":\"web\",\"truncated\":false,\"in_reply_to_status_id\":null,\"in_reply_to_status_id_str\":null,\"in_reply_to_user_id\":null,\"in_reply_to_user_id_str\":null,\"in_reply_to_screen_name\":null,\"user\":{\"id\":27260086,\"id_str\":\"27260086\",\"name\":\"Justin Bieber\",\"screen_name\":\"justinbieber\",\"location\":\"All Around The World\",\"description\":\"#BELIEVE is on ITUNES and in STORES WORLDWIDE! - SO MUCH LOVE FOR THE FANS...you are always there for me and I will always be there for you. MUCH LOVE. thanks\",\"url\":\"http:\\/\\/www.youtube.com\\/justinbieber\",\"protected\":false,\"followers_count\":25496377,\"friends_count\":123287,\"listed_count\":543680,\"created_at\":\"Sat Mar 28 16:41:22 +0000 2009\",\"favourites_count\":8,\"utc_offset\":-18000,\"time_zone\":\"Eastern Time (US & Canada)\",\"geo_enabled\":false,\"verified\":true,\"statuses_count\":17356,\"lang\":\"en\",\"contributors_enabled\":false,\"is_translator\":false,\"profile_background_color\":\"C0DEED\",\"profile_background_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_tile\":false,\"profile_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_link_color\":\"0084B4\",\"profile_sidebar_border_color\":\"C0DEED\",\"profile_sidebar_fill_color\":\"DDEEF6\",\"profile_text_color\":\"333333\",\"profile_use_background_image\":true,\"show_all_inline_media\":false,\"default_profile\":false,\"default_profile_image\":false,\"following\":null,\"follow_request_sent\":null,\"notifications\":null},\"geo\":null,\"coordinates\":null,\"place\":null,\"contributors\":null,\"retweet_count\":11427,\"favorited\":false,\"retweeted\":false},
                   {\"created_at\":\"Wed Jul 25 02:48:58 +0000 2012\",\"id\":227958593167708160,\"id_str\":\"227958593167708160\",\"text\":\"yep...It is CONFIRMED! Going to give you the begginning of the #AsLongAsYouLoveMeVideo tomorrow on @nbcagt !!! GET READY\",\"source\":\"web\",\"truncated\":false,\"in_reply_to_status_id\":null,\"in_reply_to_status_id_str\":null,\"in_reply_to_user_id\":null,\"in_reply_to_user_id_str\":null,\"in_reply_to_screen_name\":null,\"user\":{\"id\":27260086,\"id_str\":\"27260086\",\"name\":\"Justin Bieber\",\"screen_name\":\"justinbieber\",\"location\":\"All Around The World\",\"description\":\"#BELIEVE is on ITUNES and in STORES WORLDWIDE! - SO MUCH LOVE FOR THE FANS...you are always there for me and I will always be there for you. MUCH LOVE. thanks\",\"url\":\"http:\\/\\/www.youtube.com\\/justinbieber\",\"protected\":false,\"followers_count\":25496377,\"friends_count\":123287,\"listed_count\":543680,\"created_at\":\"Sat Mar 28 16:41:22 +0000 2009\",\"favourites_count\":8,\"utc_offset\":-18000,\"time_zone\":\"Eastern Time (US & Canada)\",\"geo_enabled\":false,\"verified\":true,\"statuses_count\":17356,\"lang\":\"en\",\"contributors_enabled\":false,\"is_translator\":false,\"profile_background_color\":\"C0DEED\",\"profile_background_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_tile\":false,\"profile_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_link_color\":\"0084B4\",\"profile_sidebar_border_color\":\"C0DEED\",\"profile_sidebar_fill_color\":\"DDEEF6\",\"profile_text_color\":\"333333\",\"profile_use_background_image\":true,\"show_all_inline_media\":false,\"default_profile\":false,\"default_profile_image\":false,\"following\":null,\"follow_request_sent\":null,\"notifications\":null},\"geo\":null,\"coordinates\":null,\"place\":null,\"contributors\":null,\"retweet_count\":14816,\"favorited\":false,\"retweeted\":false},
                   {\"created_at\":\"Tue Jul 24 21:24:13 +0000 2012\",\"id\":227876867103916032,\"id_str\":\"227876867103916032\",\"text\":\"Michael Madsen likes this idea @nbcagt - 1 minute of #AsLongAsYouLoveMeVideo\",\"source\":\"web\",\"truncated\":false,\"in_reply_to_status_id\":null,\"in_reply_to_status_id_str\":null,\"in_reply_to_user_id\":null,\"in_reply_to_user_id_str\":null,\"in_reply_to_screen_name\":null,\"user\":{\"id\":27260086,\"id_str\":\"27260086\",\"name\":\"Justin Bieber\",\"screen_name\":\"justinbieber\",\"location\":\"All Around The World\",\"description\":\"#BELIEVE is on ITUNES and in STORES WORLDWIDE! - SO MUCH LOVE FOR THE FANS...you are always there for me and I will always be there for you. MUCH LOVE. thanks\",\"url\":\"http:\\/\\/www.youtube.com\\/justinbieber\",\"protected\":false,\"followers_count\":25496377,\"friends_count\":123287,\"listed_count\":543680,\"created_at\":\"Sat Mar 28 16:41:22 +0000 2009\",\"favourites_count\":8,\"utc_offset\":-18000,\"time_zone\":\"Eastern Time (US & Canada)\",\"geo_enabled\":false,\"verified\":true,\"statuses_count\":17356,\"lang\":\"en\",\"contributors_enabled\":false,\"is_translator\":false,\"profile_background_color\":\"C0DEED\",\"profile_background_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_tile\":false,\"profile_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_link_color\":\"0084B4\",\"profile_sidebar_border_color\":\"C0DEED\",\"profile_sidebar_fill_color\":\"DDEEF6\",\"profile_text_color\":\"333333\",\"profile_use_background_image\":true,\"show_all_inline_media\":false,\"default_profile\":false,\"default_profile_image\":false,\"following\":null,\"follow_request_sent\":null,\"notifications\":null},\"geo\":null,\"coordinates\":null,\"place\":null,\"contributors\":null,\"retweet_count\":13203,\"favorited\":false,\"retweeted\":false},
                   {\"created_at\":\"Tue Jul 24 21:23:41 +0000 2012\",\"id\":227876733389524993,\"id_str\":\"227876733389524993\",\"text\":\"so im thinking about giving a minute of the #AsLongAsYouLoveMeVideo to @nbcagt for their show tomorrow? Thoughts? ask them\",\"source\":\"web\",\"truncated\":false,\"in_reply_to_status_id\":null,\"in_reply_to_status_id_str\":null,\"in_reply_to_user_id\":null,\"in_reply_to_user_id_str\":null,\"in_reply_to_screen_name\":null,\"user\":{\"id\":27260086,\"id_str\":\"27260086\",\"name\":\"Justin Bieber\",\"screen_name\":\"justinbieber\",\"location\":\"All Around The World\",\"description\":\"#BELIEVE is on ITUNES and in STORES WORLDWIDE! - SO MUCH LOVE FOR THE FANS...you are always there for me and I will always be there for you. MUCH LOVE. thanks\",\"url\":\"http:\\/\\/www.youtube.com\\/justinbieber\",\"protected\":false,\"followers_count\":25496377,\"friends_count\":123287,\"listed_count\":543680,\"created_at\":\"Sat Mar 28 16:41:22 +0000 2009\",\"favourites_count\":8,\"utc_offset\":-18000,\"time_zone\":\"Eastern Time (US & Canada)\",\"geo_enabled\":false,\"verified\":true,\"statuses_count\":17356,\"lang\":\"en\",\"contributors_enabled\":false,\"is_translator\":false,\"profile_background_color\":\"C0DEED\",\"profile_background_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_tile\":false,\"profile_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_link_color\":\"0084B4\",\"profile_sidebar_border_color\":\"C0DEED\",\"profile_sidebar_fill_color\":\"DDEEF6\",\"profile_text_color\":\"333333\",\"profile_use_background_image\":true,\"show_all_inline_media\":false,\"default_profile\":false,\"default_profile_image\":false,\"following\":null,\"follow_request_sent\":null,\"notifications\":null},\"geo\":null,\"coordinates\":null,\"place\":null,\"contributors\":null,\"retweet_count\":13737,\"favorited\":false,\"retweeted\":false},
                   {\"created_at\":\"Tue Jul 24 10:24:58 +0000 2012\",\"id\":227710959639212032,\"id_str\":\"227710959639212032\",\"text\":\"@judahsmith love you too brosef\",\"source\":\"\\u003ca href=\\\"http:\\/\\/www.echofon.com\\/\\\" rel=\\\"nofollow\\\"\\u003eEchofon\\u003c\\/a\\u003e\",\"truncated\":false,\"in_reply_to_status_id\":227590308035186688,\"in_reply_to_status_id_str\":\"227590308035186688\",\"in_reply_to_user_id\":15079315,\"in_reply_to_user_id_str\":\"15079315\",\"in_reply_to_screen_name\":\"judahsmith\",\"user\":{\"id\":27260086,\"id_str\":\"27260086\",\"name\":\"Justin Bieber\",\"screen_name\":\"justinbieber\",\"location\":\"All Around The World\",\"description\":\"#BELIEVE is on ITUNES and in STORES WORLDWIDE! - SO MUCH LOVE FOR THE FANS...you are always there for me and I will always be there for you. MUCH LOVE. thanks\",\"url\":\"http:\\/\\/www.youtube.com\\/justinbieber\",\"protected\":false,\"followers_count\":25496377,\"friends_count\":123287,\"listed_count\":543680,\"created_at\":\"Sat Mar 28 16:41:22 +0000 2009\",\"favourites_count\":8,\"utc_offset\":-18000,\"time_zone\":\"Eastern Time (US & Canada)\",\"geo_enabled\":false,\"verified\":true,\"statuses_count\":17356,\"lang\":\"en\",\"contributors_enabled\":false,\"is_translator\":false,\"profile_background_color\":\"C0DEED\",\"profile_background_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_background_images\\/584092392\\/4zlsn4lanbnmzg35l92k.jpeg\",\"profile_background_tile\":false,\"profile_image_url\":\"http:\\/\\/a0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_image_url_https\":\"https:\\/\\/si0.twimg.com\\/profile_images\\/2385531870\\/ffb6obdzkxc3pk7lvbw2_normal.jpeg\",\"profile_link_color\":\"0084B4\",\"profile_sidebar_border_color\":\"C0DEED\",\"profile_sidebar_fill_color\":\"DDEEF6\",\"profile_text_color\":\"333333\",\"profile_use_background_image\":true,\"show_all_inline_media\":false,\"default_profile\":false,\"default_profile_image\":false,\"following\":null,\"follow_request_sent\":null,\"notifications\":null},\"geo\":null,\"coordinates\":null,\"place\":null,\"contributors\":null,\"retweet_count\":6010,\"favorited\":false,\"retweeted\":false}
                 ]"
end