require 'sidekiq'
require 'sidekiq/web'

ENV_MAPPING = {
  'sidekiq.actionbuilder.org' => {
    name: 'production',
    redis_url:  ENV['PRODUCTION_REDIS_URL']
  },
  'sidekiq.weinteract.org' => {
    name: 'staging',
    redis_url:  ENV['STAGING_REDIS_URL']
  },
  'sidekiq.weinteractdev.org' => {
    name: 'dev',
    redis_url:  ENV['DEV_REDIS_URL']
  },
  'sidekiq.lvh.me' => {
    name: 'local',
    redis_url:  ENV['LOCAL_REDIS_URL'] || 'redis://localhost:6379'
  }
}

sidekiq_user = ENV.fetch('SIDEKIQ_USER') { 'admin' }
sidekiq_password = ENV.fetch('SIDEKIQ_PASSWORD') { 'admin' }

class SwitchEnvironment
  def initialize(app)
    @app = app
  end

  def set_redis_url(redis_url)
    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
    end
  end

  def set_label(label)
    Sidekiq.const_set(:NAME, label)
  end

  def call(env)
    req = Rack::Request.new(env)

    if env_conf = ENV_MAPPING[req.host]
      set_redis_url(env_conf[:redis_url])
      set_label(env_conf[:name].capitalize)
      @app.call(env)
    else
      [403, {}, ["Unknown url host #{req.host}"]]
    end
  end
end


Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [sidekiq_user, sidekiq_password]
end

Sidekiq::Web.define_method(:build_sessions) do  
  middlewares = self.middlewares
  return unless sessions
  middlewares.unshift [[::Rack::Session::Cookie], nil]
end

app = Rack::Builder.new do |builder|
  builder.use SwitchEnvironment
  builder.run Sidekiq::Web
end

run app
