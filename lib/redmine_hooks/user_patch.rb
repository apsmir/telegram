require_relative '../telegram_bot_helper'

module RedmineHooks
    module UserPatch
      include TelegramBotHelper
      def update
        u = find_user
        old_status = u.status if u
        super
        new_status = u.status if u
        if (old_status != User::STATUS_ACTIVE && new_status == User::STATUS_ACTIVE)
          telegram_activate_user(u)
        end
      end
    end
end

UsersController.send(:prepend, RedmineHooks::UserPatch)