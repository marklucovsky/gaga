helpers do

  # return the timeline config block from the config
  # file. IF the timeline param is passed, use that as
  # the key. if not, then use the default key from the config
  def get_timeline_config
    @config = nil
    # if a timeline param is specified, then use it as a key
    # if it fails to find a record, the lookup will return
    # nil, this will cause a second lookup using the default key
    if params[:timeline]
      @config = lookup_config_key(params[:timeline])
    end
    @config = lookup_config_key($config['default']) if !@config
    #$log.debug("@config => #{@config.pretty_inspect}")
  end

  def lookup_config_key(key)
    #$log.debug("lck(0) #{key}")
    $config['timelines'].each do |entry|
      if entry['key'] == key
        return entry
      end
    end
    return nil
  end
end