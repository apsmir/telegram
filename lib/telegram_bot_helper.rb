module TelegramBotHelper

  @bot_client = nil

  def client
    if !@bot_client
      @bot_client = Telegram::Bot::Client.new(token)
      @bot_client.async(false)
    end
    return @bot_client
  end

  def search_dir(dir, &callback)
    return if !File.exist?(dir)
    Dir.each_child(dir) do |d|
      name = File.join(dir, d)
      if File.directory?(name)
        search_dir(name, &callback)
      else
        callback.call name
      end
    end
  end

  def file_path_key(cache_path, path)
    fname = path[cache_path.to_s.size..-1].split(File::SEPARATOR, 4).last
    URI.decode_www_form_component(fname, Encoding::UTF_8)
  end

  def send_message(chat_id, text, list=[])
    Thread.new {
      begin
        client.send_message(chat_id: "#{chat_id}", text: text, reply_markup: { inline_keyboard: list })
      rescue Exception => e
        Rails.logger.error "Telegram bot error #{e}"
      end
    }
  end
  def send_photo(chat_id, file, caption)
    Thread.new {
      begin
        client.send_photo(chat_id: "#{chat_id}", photo: File.open(file), caption: caption)
      rescue Exception => e
        Rails.logger.error "Telegram bot error #{e}"
      end
    }
  end

  def send_document(chat_id, file, caption)
    Thread.new {
      begin
        client.send_document(chat_id: "#{chat_id}", document: File.open(file), caption: caption)
      rescue Exception => e
        Rails.logger.error "Telegram bot error #{e}"
      end
    }
  end

  def set_chat_menu(chat_id)
    Thread.new {
      begin
        cmd = t('telegram_webhooks.menu').map{|s|
          {command: s[:item][:command], description: s[:item][:description]}
        }
        client.send_message(chat_id: "#{chat_id}", text: t('tg_user_activated'))
        client.set_my_commands({commands: cmd, scope: { type: 'chat', chat_id: chat_id }})
        client.set_chat_menu_button( {chat_id: chat_id, menu_button: { type: 'commands' }})
      rescue Exception => e
        Rails.logger.error "Telegram bot error #{e}"
      end
    }
  end

  def token
    return Setting.plugin_telegram['bot_token']
  end

  def lang
    return Setting.default_language
  end

  def telegram_activate_user (user)
    store = Telegram::Bot::UpdatesController.session_store
    cache_path = store.cache_path
    search_dir(cache_path) do |fname|
      session = store.fetch(file_path_key(cache_path, fname))
      chat_id = session['chat_id']
      if chat_id && (session['user_id'] == user.id)
        set_chat_menu(chat_id)
      end
    end
  end

end