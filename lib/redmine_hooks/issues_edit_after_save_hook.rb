module RedmineHooks
  class IssuesEditAfterSaveHook < Redmine::Hook::Listener
    def controller_issues_edit_after_save (context = { })
      #Telegram::Bot::respond_with :message, text: 'Изменения в задаче'
    end
  end
end
