module RedmineHooks
  class IssuesEditAfterSaveHook < Redmine::Hook::Listener
    include Telegram::Bot::ConfigMethods

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

    def controller_issues_edit_after_save (context = { })
      if Setting.plugin_telegram['bot_enabled'].to_i < 1
        return
      end
      issue = context[:issue]
      notes = context[:journal].attributes['notes']
      created_on = context[:journal].attributes['created_on']
      msg_time = issue.author.convert_time_to_user_timezone(created_on).strftime('%H:%M')

      if notes
        user_id = context[:journal].attributes['user_id']
        user = User.find_by_id(user_id)
        Thread.new {
          begin
            store = Telegram::Bot::UpdatesController.session_store
            cache_path = store.cache_path
            search_dir(cache_path) do |fname|
              key = file_path_key(cache_path, fname)
              session = store.fetch(key)
              chat_id = session['chat_id']
              if chat_id && (session['user_id'] == issue.author_id)
                token = Setting.plugin_telegram['bot_token']
                client = Telegram::Bot::Client.new(token)
                client.async(false)
                client.send_message(chat_id: "#{chat_id}",
                                    text: "#{msg_time} #{user.firstname} ответил: #{notes}")
              end
            end
          rescue Exception => e
            Rails.logger.error "Telegram bot error #{e}"
          end
        }
      end
    end
  end
end
