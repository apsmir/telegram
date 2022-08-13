module Poller
  def self.logger
    Rails.logger
  end

  def self.init()
    Telegram.bots_config = {
      default: {
        token: Setting.plugin_telegram['bot_token'],
        username: Setting.plugin_telegram['bot_username']
      }
    }
    Telegram::Bot::UpdatesController.session_store  = :file_store, "plugins/telegram/cache"
  end

  def self.start()
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
          sleep 1.minute
          init()
        end
      rescue SystemExit, SignalException
        logger.error "Telegram poller stopped"
        break
      rescue Exception => e
        logger.error "Telegram bot error #{e}"
        sleep 5.second
      end
    end
  end
end
