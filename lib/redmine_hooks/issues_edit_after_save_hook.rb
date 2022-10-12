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

    def send_message(chat_id, text, list=[])
      Thread.new {
        begin
          client = Telegram::Bot::Client.new(token)
          client.async(false)
          client.send_message(chat_id: "#{chat_id}", text: text, reply_markup: { inline_keyboard: list })
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
          client = Telegram::Bot::Client.new(token)
          client.async(false)
          client.send_photo(chat_id: "#{chat_id}", photo: File.open(file), caption: caption)
        rescue Exception => e
          Rails.logger.error "Telegram bot error #{e}"
        end
      }
    end

    def send_document(chat_id, file, caption)
      Thread.new {
        begin
          client = Telegram::Bot::Client.new(token)
          client.async(false)
          client.send_document(chat_id: "#{chat_id}", document: File.open(file), caption: caption)
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

    def get_issue_button(issue)
      callback_action = 'set_issue_context'
      return [[{
            text: ll(lang, :tg_select_issue, caption:issue.to_s) ,
            callback_data: "{ \"action\": \"#{callback_action}\", \"issue_id\": \"#{issue.id}\" }"
      }]]
    end

    def convert_time_to_user_timezone(user, time)
      if user.time_zone
        time.in_time_zone(user.time_zone)
      else
        time.utc? ? time.localtime : time
      end
    end

    def project_ids
      return Setting.plugin_telegram['notified_project_ids'].to_a
    end

    def project_included(project)
      return project_ids.include?(project.id.to_s)
    end

    def controller_issues_edit_after_save (context = { })
      return unless Setting.plugin_telegram['bot_enabled'].to_i > 0

      issue = context[:issue]
      journal = context[:journal]

      return unless project_included(issue.project)

      if !issue.notes.empty? || !issue.closed_on.nil? || journal
        d = journal.created_on
        d = Time.now.utc if d.nil?
        msg_time = convert_time_to_user_timezone(issue.author, d).strftime('%H:%M')
        user = User.find_by_id(journal.user_id)
        store = Telegram::Bot::UpdatesController.session_store
        cache_path = store.cache_path
        search_dir(cache_path) do |fname|
          session = store.fetch(file_path_key(cache_path, fname))
          chat_id = session['chat_id']
          if chat_id && (session['user_id'] == issue.author_id)
            if issue.id.to_s != session['active_issue_id'].to_s
              issue_num = l(:tg_in_issue_num, id:issue.id)
              button = get_issue_button(issue)
            else
              issue_num = ''
              button = []
            end
            send_message(chat_id,
                         "#{msg_time} #{issue_num} #{user.firstname} #{l(:tg_issue_response)}: #{issue.notes}",
                         button) unless issue.notes.blank?
            sleep 0.1
            journal.details.each do |detail|
              if detail.property == 'attachment'
                att = Attachment.find_by_id(detail.prop_key)
                if att.is_image?
                 send_photo(chat_id, att.diskfile, att.description)
                else
                  send_document(chat_id, att.diskfile, att.description)
                end
              end
            end
            send_message(chat_id, "#{msg_time} #{l(:tg_issue_closed)}: #{issue.id}") unless issue.closed_on.nil?
          end
        end
      end
    end
  end
end
