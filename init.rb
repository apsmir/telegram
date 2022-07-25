Redmine::Plugin.register :telegram do
  name 'Redmine telegram bot plugin'
  author 'Alexey Smirnov'
  description 'Redmine telegram bot plugin'
  version '1.0'
  settings default: {'empty' => true}, partial: 'settings/telegram_settings'
end

Telegram.bots_config = {
  default: {
    token: Setting.plugin_telegram['bot_token'],
    username: Setting.plugin_telegram['bot_username']
  }
}

def logger
  Rails.logger
end

Telegram::Bot::UpdatesController.session_store  = :file_store, "plugins/telegram/cache"

t = Thread.new {
  logger.info "Telegram bot thread run"
  bot_run = false
  loop do
    begin
      if Setting.plugin_telegram['bot_enabled'].to_i > 0
        bot_run = true
        Telegram::Bot::UpdatesPoller.start(:default, TelegramWebhooksController)
      else
        if bot_run
          logger.info 'Telegram bot disabled'
        end
        bot_run = false
      end
    rescue Exception => e
      logger.error "Telegram bot error #{e}"
      sleep 1.minute
    end
  end
}


logger.info "Telegram bot init"