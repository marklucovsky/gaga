require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'redis'
require 'haml'
require 'json/pure'
require 'pp'
require 'logger'
require 'httpclient'
require 'lib/gaga/helpers.rb'
require 'lib/gaga/redis_timeline.rb'

# establish global logger to stdout
# use "vmc logs"" or "vmc files gaga logs/stdout.log" to view
$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG
#$log.level = Logger::INFO
#$log.level = Logger::WARN

# note the auto-magical cf auto-reconfiguration gem will
# patch in the real redis config gleaned from the environment
# this saves me from having to write understandable and straight
# forward binding code. lazy magical people like this voodoo black
# magic. I prefer the longhand approach but sigh, I'll reluctantly go
# along, until it breaks, then I will be vocal...
# $vcap_services = JSON.parse(ENV['VCAP_SERVICES']) if ENV['VCAP_SERVICES']
# redis = $vcap_services['redis-2.2'][0]
# redis_conf = {:host => redis['credentials']['hostname'],
#              :port => redis['credentials']['port'],
#              :password => redis['credentials']['password']}
# $redis = Redis.new redis_conf
$redis =  Redis.new(:host => '127.0.0.1', :port => '6379')

# load config, prep for being able to run the same logic for multiple time lines
config_file = File.expand_path("config/config.yml", "#{__FILE__}/..")
$config = File.open(config_file) do |f|
  YAML.load(f)
end

$log.debug("$config => #{$config.pretty_inspect}")
$log.debug("$redis => #{$redis.pretty_inspect}")

# return the page, rendered via haml
get '/' do
  headers['Cache-Control'] = 'no-store'
  get_timeline_config
  halt 400 if !@config

  redis_tl = RedisTimeline.new($redis, @config)
  @tweets = nil
  @tweets = redis_tl.tl if redis_tl
  @tlset = redis_tl.tlset
  #$log.debug("get/(0): #{@tweets.pretty_inspect}") if @tweets != nil

  haml :index
end

get '/boot' do
  content_type :json

  @founders = {
    "Apple"     => ["Steve Jobs", "Steve Wozniak", "Ronald Wayne"],
    "Dribbble"  => ["Dan Cederholm", "Rich Thornett"],
    "GitHub"    => ["Tom Preston-Werner", "Chris Wanstrath", "PJ Hyett"],
    "Heroku"    => ["James Lindenbaum", "Adam Wiggins", "Orion Henry"],
    "Gowalla"   => ["Josh Williams", "Scott Raymond"],
    "Square"    => ["Jack Dorsey", "Tristan O'Tierney", "Jim McKelvey"],
    "Twitter"   => ["Jack Dorsey", "Biz Stone", "Evan Williams"]
  }

  # Specify response freshness policy for HTTP caches (Cache-Control header).
  #
  # See RFC 2616 / 14.9 for more on standard cache control directives:
  # http://tools.ietf.org/html/rfc2616#section-14.9.1
  cache_control :public, :must_revalidate, :max_age => 86400

  # Set the last modified time of the resource (HTTP 'Last-Modified' header)
  # and halt if conditional GET matches.
  #
  # When the current request includes an 'If-Modified-Since' header that is
  # equal or later than the time specified, execution is immediately halted
  # with a '304 Not Modified' response.
  last_modified Date.today

  # Set the response entity tag (HTTP 'ETag' header) and halt if conditional
  # GET matches. The value argument is an identifier that uniquely
  # identifies the current version of the resource.
  #
  # When the current request includes an 'If-None-Match' header with a
  # matching etag, execution is immediately halted.
  #
  # If the request method is GET or HEAD, a '304 Not Modified'.
  # response is sent.
  etag Digest::MD5.hexdigest(@founders.to_s)

  # Sleep in order to demonstrate effect of client-side caching.
  # The first request will be slow, but if the client is obeying caching
  # directives, subsequent requests will be nearly instantaneous.
  sleep 5

  return @founders.to_json
end
