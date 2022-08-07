class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Telegram::Bot::UpdatesController::Session

  def t(key, **options)
    if key.to_s.start_with?('.')
      path = controller_path.tr('/', '.')
      defaults = [:"#{path}#{key}"]
      defaults << options[:default] if options[:default]
      options[:default] = defaults.flatten
      if session[:context].blank?
        key = "#{path}.#{action_name_i18n_key}#{key}"
      else
        key = "#{path}.#{session[:context]}#{key}"
      end
    end
    I18n.translate(key, **options)
  end

  def start!(*args)
    field = session[:field]
    if field.blank?
      clear_chat_menu
      respond_with :message, text: t('.content'), parse_mode: :Markdown
      get_filed('fio')
    else
      session[field] = args.join(' ')
      case field
      when 'fio'
        get_filed('email')
      when 'email'
        get_filed('city')
      when 'city'
        session.delete(:field)
        if register_user
          set_chat_menu
        end
        #, reply_markup: {
        #  keyboard: [t('.buttons')],
        #  resize_keyboard: true,
        #  one_time_keyboard: true,
        #  input_field_placeholder: 'test placeholder',
        #  selective: true,
        #}
      else
        session.delete(:field)
      end
    end
  end

  def register_user
    begin
      session[:user_id] = nil
      mail = session[:email]
      u = User.find_by_mail(mail)
      msg = Setting.plugin_telegram['welcome']
      if u
        respond_with :message, text: t('.user_found', login:u.login, firstname: u.firstname, lastname: u.lastname)
        respond_with :message, text: msg
      else
        u = MailHandler.new_user_from_attributes(mail, session[:fio])
        s1 = u.lastname
        u.lastname = u.firstname
        u.firstname = s1
        if u.save
          msg = t('.success') if msg.blank?
          respond_with :message, text: msg
        else
          raise Exception.new(u.errors.full_messages)
        end
      end
      session[:user_id] = u.id
      session[:chat_id] = chat_id
      return true
    rescue Exception => e
      session[:field] = nil
      respond_with :message, text: t('.register_user_error', e: e)
      return false
    end
  end

  def chat_id
    return self.chat['id']
  end

  def clear_chat_menu
    bot.set_my_commands({commands: [], scope: {type: 'chat', chat_id: chat_id}})
  end

  def set_chat_menu
    cmd = I18n.t('telegram_webhooks.menu').map{|s|
      {command: s[:item][:command], description: s[:item][:description]}
    }
    bot.set_my_commands({commands: cmd, scope: { type: 'chat', chat_id: chat_id }})
    bot.set_chat_menu_button( {chat_id: chat_id, menu_button: { type: 'commands' }})
  end

  def new_issue!(*args)
    list_projects ('get_issue_description')
  end

  def get_issue_description (action_obj)
    session[:active_project_id] = action_obj.project_id
    new_issue_description = session[:new_issue_description]
    if new_issue_description.blank?
      respond_with :message, text: t('.get_issue_description')
      save_context :create_issue
    else
      save_context :create_issue
      create_issue(new_issue_description)
    end
  end

  def create_issue(*args)
    begin
      attributes={}
      issue = Issue.new(attributes.reverse_merge(:notify => false))
      issue.project = Project.find(session[:active_project_id])
      issue.tracker ||= issue.project.trackers.first
      issue.subject = args.take(5).join(' ')
      issue.author ||= User.find(session[:user_id])
      issue.description = t('.description',
                            fio: session[:fio],
                            email: session[:email],
                            phone: session[:phone],
                            text: args.join(' '))
      session[:new_issue_description] = nil
      if issue.save
        session[:active_issue] = issue.id
        respond_with :message, text: t('.success', id: issue.id)
        save_context :add_description_context
      else
        raise Exception.new(issue.errors.full_messages)
      end
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def add_photo_to_issue(issue, user)
    begin
      file = bot.get_file({file_id: payload['photo'].last['file_id']})
      file_name = file['result']['file_path']
      uri = "https://api.telegram.org/file/bot#{bot.token}/#{file_name}"
      response = bot.client.get(uri)
      att = Attachment.create(:container => issue,
                              :file => response.body,
                              :filename => file_name,
                              :author => user)
      issue.attachments << att
      return att
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def add_description_context(*args)
    begin
      issue = Issue.find(session[:active_issue])
      user = User.find_by_id(session['user_id'])
      if issue.closed_on.nil?
        attachment = add_photo_to_issue(issue, user) unless payload['photo'].nil?
        if issue.journals.empty?
          issue.description+= "\n" +args.join(' ')
        else
          issue.init_journal(user, args.join(' '))
          issue.current_journal.journalize_attachment(attachment, :added) unless attachment.nil?
        end
        save_context :add_description_context
        if issue.save
          respond_with :message, text: t('.success', id: issue.id)
        else
          raise Exception.new(issue.errors.full_messages)
        end
      else
        # create new issue
        session[:active_issue] = nil
        session[:new_issue_description] = args
        save_context :new_issue
        new_issue!([])
      end
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def u_time(utc_time, issue)
    issue.author.convert_time_to_user_timezone(utc_time).strftime('%d-%m-%Y %H:%M')
  end

  def set_issue_context(action_obj)
    session[:active_issue] = action_obj.issue_id
    save_context :set_issue_context
    issue = Issue.find(action_obj.issue_id)
    closed_on = issue.closed_on.nil? ? nil: t('.time_close', closed_on: u_time(issue.closed_on, issue))
    if !issue.journals.nil?
      history = issue.journals.map { |journal|
        detail = journal.details.map {|d|
          template =
            case d[:property]
            when 'attachment'
              '.detail_file'
            when 'attr'
              '.detail_attr'
            else
              '.detail'
            end
          t(template,
            property:d[:property],
            prop_key:d[:prop_key],
            value: d[:value])
        }
        t('.history',
          created_on: u_time(journal.created_on, issue),
          user: journal.user,
          notes: journal.notes,
          detail: detail.empty? ? nil: detail
        )
      }
    end
    respond_with :message, text: t('.notice',
                                   caption: issue.to_s,
                                   description: issue.description,
                                   created_on: u_time(issue.created_on,issue),
                                   assigned: issue.assigned_to,
                                   status: issue.status,
                                   closed_on: closed_on,
                                   history: history.join("\n"))
    save_context :add_description_context
  end

  def arc_issues!(*args)
    callback_action = 'set_issue_context'
    list = Issue.
            where(author_id: session[:user_id]).
            where.not(closed_on: nil).
            map {|issue| [{
              text: t('.caption', caption:issue.to_s) ,
              callback_data: "{ \"action\": \"#{callback_action}\", \"issue_id\": \"#{issue.id}\" }"
            }]}
    respond_with :message, text: t('.prompt'), reply_markup: { inline_keyboard: list }
  end

  def my_issues!(*args)
    callback_action = 'set_issue_context'
    list = Issue.where(author_id: session[:user_id], closed_on: nil).map {|issue|
        [{
          text: t('.caption', caption:issue.to_s) ,
          callback_data: "{ \"action\": \"#{callback_action}\", \"issue_id\": \"#{issue.id}\" }"
         }]
      }
      respond_with :message, text: t('.prompt'), reply_markup: { inline_keyboard: list }
  end

  def list_projects (callback_action = action_name)
    list = Project.find_each.map {|project|
      {text: project.name, callback_data: "{ \"action\": \"#{callback_action}\", \"project_id\": \"#{project.id}\" }"}
    }
    respond_with :message, text: t('.prompt'), reply_markup: {
      inline_keyboard: [list],
    }
  end

  def callback_query(data)
    obj = JSON.parse(data, object_class: OpenStruct)
    case obj.action
      when 'get_issue_description'
        get_issue_description(obj)
        return
      when 'set_issue_context'
        set_issue_context(obj)
        return
    else
      answer_callback_query 'description added'
    end
  end

  def projects!(*)
    list_projects
  end

  def get_filed( field)
    respond_with :message, text: t('.'+field)
    session[:field] = field
    save_context action_name
  end

  def help!(*)
    msg = Setting.plugin_telegram['help']
    msg = t('.content') if msg.blank?
    respond_with :message, text: msg
  end

  def memo!(*args)
    if args.any?
      session[:memo] = args.join(' ')
      respond_with :message, text: t('.notice')
    else
      respond_with :message, text: t('.prompt')
      save_context :memo!
    end
  end

  def remind_me!(*)
    to_remind = session.delete(:memo)
    reply = to_remind || t('.nothing')
    respond_with :message, text: reply
  end

  def keyboard!(value = nil, *)
    if value
      respond_with :message, text: t('.selected', value: value)
    else
      save_context :keyboard!
      respond_with :message, text: t('.prompt'), reply_markup: {
        keyboard: [t('.buttons')],
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true,
      }
    end
  end

  def inline_keyboard!(*)
    respond_with :message, text: t('.prompt'), reply_markup: {
      inline_keyboard: [
        [
          {text: t('.alert'), callback_data: 'alert'},
          {text: t('.no_alert'), callback_data: 'no_alert'},
        ],
        [{text: t('.repo'), url: 'https://github.com/telegram-bot-rb/telegram-bot'}],
      ],
    }
  end

  def inline_query(query, _offset)
    query = query.first(10) # it's just an example, don't use large queries.
    t_description = t('.description')
    t_content = t('.content')
    results = Array.new(5) do |i|
      {
        type: :article,
        title: "#{query}-#{i}",
        id: "#{query}-#{i}",
        description: "#{t_description} #{i}",
        input_message_content: {
          message_text: "#{t_content} #{i}",
        },
      }
    end
    answer_inline_query results
  end

  # As there is no chat id in such requests, we can not respond instantly.
  # So we just save the result_id, and it's available then with `/last_chosen_inline_result`.
  def chosen_inline_result(result_id, _query)
    session[:last_chosen_inline_result] = result_id
  end

  def last_chosen_inline_result!(*)
    result_id = session[:last_chosen_inline_result]
    if result_id
      respond_with :message, text: t('.selected', result_id: result_id)
    else
      respond_with :message, text: t('.prompt')
    end
  end

  def message(message)
    respond_with :message, text: t('.content', text: message['text'])
  end

  def action_missing(action, *_args)
    if action_type == :command
      respond_with :message,
        text: t('telegram_webhooks.action_missing.command', command: action_options[:command])
    end
  end
end

