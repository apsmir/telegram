require File.dirname(__FILE__) + '/lib/redmine_hooks/issues_edit_after_save_hook.rb'
require File.dirname(__FILE__) + '/lib/redmine_hooks/user_patch.rb'
require File.dirname(__FILE__) + '/lib/poller.rb'

Redmine::Plugin.register :telegram do
  name 'Redmine telegram bot plugin'
  author 'Alexey Smirnov'
  description 'Redmine telegram bot plugin'
  version '1.1'
  settings default: {'empty' => true}, partial: 'settings/telegram_settings'
end

Poller::init()

if Rails.env.development?
  console = ActiveSupport::Logger.new(STDERR)
  Rails.logger.extend ActiveSupport::Logger.broadcast console
  t = Thread.new {
   Poller::start()
}
end
