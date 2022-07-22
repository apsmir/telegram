#require 'telegram/bot/routes_helper'

Redmine::Plugin.register :telegram do
  #require 'custom_field_sql/custom_fields/formats/sql'
  #require 'custom_sql_search_hook'
  #require 'config/routes.rb'
  name 'Redmine telegram bot plugin'
  author 'Alexey Smirnov'
  description 'Redmine telegram bot plugin'
  version '1.0'
  #url 'https://github.com/apsmir/custom_field_sql'
  settings default: {'empty' => true}, partial: 'settings/telegram_settings'
end

Telegram.bots_config = {
  default: {
    # token: '5324031123:AAFJxIwkE0SFwo6xaF_Es2tA6ikaNK7RtRk',
    # username: silent1_bot
    token: Setting.plugin_telegram['bot_token'],
    username: Setting.plugin_telegram['bot_username']
  }
}

Telegram::Bot::UpdatesController.session_store  = :file_store, "plugins/telegram/cache"

t = Thread.new {
  bot_run = false
  loop do
    begin
      if Setting.plugin_telegram['bot_enabled'].to_i > 0
        bot_run = true
        Telegram::Bot::UpdatesPoller.start(:default, TelegramWebhooksController)
      else
        if bot_run
          puts 'telegram bot disabled'
        end
        bot_run = false
      end
    rescue Exception => e
      puts "Telegram bot error #{e}"
      sleep 1.minute
    end
  end
}
#Telegram.bot.get_updates
# Telegram.bot == Telegram.bots[:default] # true
#Telegram.bot.send_message(:default, 'hello')
#Telegram.bots[:chat].send_message('hello')
#t = Thread.new {
#    i = 100
#  while i > 0
#    puts i
#    sleep (1)
#    i = i -1
#  end
#}
#sleep(10)
#Thread.new { raise 'hell' }

puts "hello"