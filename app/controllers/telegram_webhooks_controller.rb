require 'ostruct'
require 'user'
class TelegramWebhooksController < Telegram::Bot::UpdatesController

  before_action :check_registration, except: [:start!]

  include Telegram::Bot::UpdatesController::MessageContext
  include Telegram::Bot::UpdatesController::Session
  include Redmine::I18n
  include Redmine::Hook::Helper

  def t(key, **options)
    if key.to_s.start_with?('.')
      @controller_path_tr = controller_path.tr('/', '.')
      path = @controller_path_tr
      defaults = [:"#{path}#{key}"]
      defaults << options[:default] if options[:default]
      options[:default] = defaults.flatten
      if session[:context].blank?
        key = "#{path}.#{action_name_i18n_key}#{key}"
      else
        key = "#{path}.#{session[:context]}#{key}"
      end
    end
    ll(Setting.default_language, key, options)
  end

  def check_registration
    if session[:user_id].blank?
      msg = t('tg_user_not_registered')
    else
      u = User.find(session[:user_id])
      if u
        if u.status == User::STATUS_ACTIVE
          return true
        else
          msg = t('tg_is_blocked')
        end
      else
        msg = t('tg_user_not_found')
      end
    end
    clear_chat_menu
    respond_with :message, text: msg
    throw(:abort)
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
        register_user
      else
        session.delete(:field)
      end
    end
  end

  def wait_activation(*args)
    bot_context :wait_activation
    respond_with :message, text: t('.content')
  end

  def register_user
    begin
      session[:user_id] = nil
      session[:active_project_id] = nil
      session[:active_issue_id] = nil
      session[:field] = nil
      mail = session[:email]
      u = User.find_by_mail(mail)
      welcome_msg = Setting.plugin_telegram['welcome']
      welcome_msg = t('.success') if welcome_msg.blank?
      if u
        if u.active?
         respond_with :message, text: t('.user_found', login:u.login, firstname: u.firstname, lastname: u.lastname)
         set_chat_menu
        else
          wait_activation
        end

        #respond_with :message, text: welcome_msg
      else
        u = MailHandler.new_user_from_attributes(mail, session[:fio])
        s1 = u.lastname
        u.lastname = u.firstname
        u.firstname = s1
        u.status = (Setting.self_registration == '3' ? User::STATUS_REGISTERED: User::STATUS_LOCKED)
        if u.save
          if u.active?
            respond_with :message, text: welcome_msg
            set_chat_menu
            new_issue!(nil)
          else
            wait_activation
          end
        else
          raise Exception.new(u.errors.full_messages)
        end
      end
      session[:user_id] = u.id
      session[:chat_id] = chat_id
      return true
    rescue Exception => e
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
    cmd = t('telegram_webhooks.menu').map{|s|
      {command: s[:item][:command], description: s[:item][:description]}
    }
    bot.set_my_commands({commands: cmd, scope: { type: 'chat', chat_id: chat_id }})
    bot.set_chat_menu_button( {chat_id: chat_id, menu_button: { type: 'commands' }})
  end

  def list_projects_context(*args)
    list_projects ('get_issue_description')
  end

  def new_issue!(*args)
    list_projects ('get_issue_description')
  end

  def get_issue_description (action_obj)
    bot_context :create_issue
    session[:active_project_id] = action_obj.project_id
    new_issue_description = session[:new_issue_description]
    if new_issue_description.blank?
      respond_with :message, text: t('.get_issue_description')
    else
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
      issue.notify = true
      issue.description = t('.description',
                            fio: session[:fio],
                            email: session[:email],
                            city: session[:city],
                            text: args.join(' '))
      session[:new_issue_description] = nil
      if issue.save
        session[:active_issue_id] = issue.id
        respond_with :message, text: t('.success', id: issue.id)
        call_hook(:controller_issues_new_after_save, {:params => args, :issue => issue})
        bot_context :add_description_context
      else
        raise Exception.new(issue.errors.full_messages)
      end
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def add_file_to_issue(issue, user, type)
    begin
      item = payload[type]
      return if item.nil?
      if item.kind_of?(Array)
        file_id = item.last['file_id']
      else
        file_id = item['file_id']
        file_name = payload[type]['file_name']
      end
      file = bot.get_file({file_id: file_id})
      file_name ||= file['result']['file_path']
      uri = "https://api.telegram.org/file/bot#{bot.token}/#{file['result']['file_path']}"
      response = bot.client.get(uri)
      att = Attachment.create(:container => issue,
                              :file => response.body,
                              :filename => file_name,
                              :author => user,
                              :description => payload['caption'])
      journal = issue.init_journal(user)
      journal.notes = payload['caption']
      issue.attachments << att
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def session_user
    User.find_by_id(session['user_id'])
  end
  def add_description_context(*args)
    begin
      issue = Issue.find(session[:active_issue_id])
      user = User.find_by_id(session['user_id'])
      if available_project_ids.include?(issue.project_id) && issue.closed_on.nil?
        if issue.journals.empty? && session['user_id'] == issue.author_id
          issue.description+= "\n" +args.join(' ')
        else
          issue.init_journal(user, args.join(' '))
        end
        add_file_to_issue(issue, user, 'photo')
        add_file_to_issue(issue, user, 'document')
        add_file_to_issue(issue, user, 'audio')
        add_file_to_issue(issue, user, 'video')
        add_file_to_issue(issue, user, 'voice')
        add_file_to_issue(issue, user, 'video_note')
        bot_context :add_description_context
        if issue.save
          respond_with :message, text: t('.success', id: issue.id)
          call_hook(
            :controller_issues_edit_after_save,
            {:params => args, :issue => issue,
             :journal => issue.current_journal}
          )
        else
          raise Exception.new(issue.errors.full_messages)
        end
      else
        # create new issue
        session[:active_issue_id] = nil
        session[:new_issue_description] = args
        bot_context :new_issue
        new_issue!([])
      end
    rescue Exception => e
      respond_with :message, text: t('.error', e: e)
    end
  end

  def u_time(utc_time, issue)
    convert_time_to_user_timezone(issue.author, utc_time).strftime('%d-%m-%Y %H:%M')
  end

  def convert_time_to_user_timezone(user, time)
    if user.time_zone
      time.in_time_zone(user.time_zone)
    else
      time.utc? ? time.localtime : time
    end
  end

  def set_issue_context(action_obj)
    session[:active_issue_id] = action_obj.issue_id
    bot_context :set_issue_context
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
    bot_context :add_description_context
  end

  def arc_issues!(*args)
    callback_action = 'set_issue_context'
    list = Issue.
            where(author_id: session[:user_id], project_id: available_project_ids).
            where.not(closed_on: nil).
            map {|issue| [{
              text: t('.caption', caption:issue.to_s) ,
              callback_data: "{ \"action\": \"#{callback_action}\", \"issue_id\": \"#{issue.id}\" }"
            }]}
    if list.size == 0
      respond_with :message, text: t('.no_closed_issues')
    else
      respond_with :message, text: t('.prompt'), reply_markup: { inline_keyboard: list }
    end
    bot_context session[:bot_context]
  end

  def project_ids
    return Setting.plugin_telegram['notified_project_ids'].to_a
  end

  def available_project_ids
    list = Project.
      where(id: project_ids).
      where(Project.visible_condition(session_user))
    list.ids
  end

  def my_issues!(*args)
    callback_action = 'set_issue_context'
    list = Issue.
        where('author_id=? or assigned_to_id=?',  session[:user_id], session[:user_id]).
        where(closed_on: nil).
        where(project_id: available_project_ids).
        map {|issue|
        [{
          text: t('.caption', caption:issue.to_s) ,
          callback_data: "{ \"action\": \"#{callback_action}\", \"issue_id\": \"#{issue.id}\" }"
         }]
      }
      respond_with :message, text: t('.prompt'), reply_markup: { inline_keyboard: list }
    bot_context session[:bot_context]
  end

  def list_projects (callback_action = action_name)
    bot_context :list_projects_context
    list = Project.
      where(id: project_ids).
      where(Project.visible_condition(session_user)).
      map {|project|
      [{text: project.name, callback_data: "{ \"action\": \"#{callback_action}\", \"project_id\": \"#{project.id}\" }"}]
    }
    if list.size == 0
      respond_with :message, text: t('.no_projects_available')
    else
      respond_with :message, text: t('.prompt'), reply_markup: { inline_keyboard: list }
    end
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
    bot_context action_name
  end

  def help!(*)
    msg = Setting.plugin_telegram['help']
    msg = t('.content') if msg.blank?
    respond_with :message, text: msg
    puts "Setting.default_language=#{Setting.default_language}"
    bot_context session[:bot_context]
  end

  def keyboard!(value = nil, *)
    if value
      respond_with :message, text: t('.selected', value: value)
    else
      bot_context :keyboard!
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

  def message(message)
    respond_with :message, text: t('.content', text: message['text'])
  end

  def action_missing(action, *_args)
    if action_type == :command
      respond_with :message,
        text: t('telegram_webhooks.action_missing.command', command: action_options[:command])
      bot_context session[:bot_context]
    end
  end

  def bot_context(context)
    save_context context
    session[:bot_context] = context
  end

end

