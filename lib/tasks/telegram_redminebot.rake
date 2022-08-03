namespace :telegram do
  namespace :redminebot do
    desc 'Run poller. It broadcasts Rails.logger to STDOUT in dev like `rails s` do. ' \
      'Use LOG_TO_STDOUT to enable/disable broadcasting.'
    task :poller do
      ENV['BOT_POLLER_MODE'] = 'true'
      Rake::Task['environment'].invoke
      if ENV.fetch('LOG_TO_STDOUT') { Rails.env.development? }.present?
        console = ActiveSupport::Logger.new(STDERR)
        Rails.logger.extend ActiveSupport::Logger.broadcast console
      end
      Poller::start()
    end
  end
end
