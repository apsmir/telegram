module RedmineHooks
  class IssuesEditAfterSaveHook < Redmine::Hook::Listener
    #include Telegram::Bot::ConfigMethods
    #include Telegram::Bot::UpdatesController::Translation

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

    def send_message(chat_id, text)
      Thread.new {
        begin
          client = Telegram::Bot::Client.new(Setting.plugin_telegram['bot_token'])
          client.async(false)
          client.send_message(chat_id: "#{chat_id}", text: text)
        rescue Exception => e
          Rails.logger.error "Telegram bot error #{e}"
        end
      }
    end


    def get_files(context)
      files = []
      journal = context[:journal]
      if !journal.nil? && journal.details
        journal.details.each do |detail|
          if detail.property == 'attachment'
            files.add(Attachment.find_by_id(detail.prop_key).diskfile)
          end
        end
      end
      return files
    end

    def send_photo(chat_id, file, caption)
      Thread.new {
        begin
          client = Telegram::Bot::Client.new(Setting.plugin_telegram['bot_token'])
          client.async(false)
          client.send_photo(chat_id: "#{chat_id}", photo: File.open(file), caption: caption)
        rescue Exception => e
          Rails.logger.error "Telegram bot error #{e}"
        end
      }
    end

    def controller_issues_edit_after_save (context = { })
      return unless Setting.plugin_telegram['bot_enabled'].to_i > 0

      issue = context[:issue]
      journal = context[:journal]

      if !issue.notes.empty? || !issue.closed_on.nil? || journal
        msg_time = issue.author.convert_time_to_user_timezone(journal.created_on).strftime('%H:%M')
        user = User.find_by_id(journal.user_id)
        store = Telegram::Bot::UpdatesController.session_store
        cache_path = store.cache_path
        search_dir(cache_path) do |fname|
          session = store.fetch(file_path_key(cache_path, fname))
          chat_id = session['chat_id']
          if chat_id && (session['user_id'] == issue.author_id)
            send_message(chat_id, "#{msg_time} #{user.firstname} #{l(:tg_issue_response)}: #{issue.notes}") unless issue.notes.empty?
            sleep 0.1
            journal.details.each do |detail|
              if detail.property == 'attachment'
                att = Attachment.find_by_id(detail.prop_key)
                send_photo(chat_id, att.diskfile, att.description) if att.is_image?
              end
            end
            send_message(chat_id, "#{msg_time} #{l(:tg_issue_closed)}: #{issue.id}") unless issue.closed_on.nil?
          end
        end
      end
    end
  end
end
