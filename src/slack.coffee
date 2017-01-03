{EventEmitter} = require 'events'
{inspect} = require 'util'
_ = require 'lodash'
request = require 'request'
SlackBot = require.main.require 'hubot-slack/src/bot'

class Slack extends EventEmitter
  @actionListener = {}

  constructor: (@robot, options={})->
    unless options.__from_get_instance?
      # constructorで例外飛ばすの良くない？
      # Unanble to load /path/to/scripts/hoge: undefinedとだけエラーが出る
      # hubot-script読み込み時の例外は仕様的にキャッチできない？
      throw "should be instanced by getInstance()"
    @robot.logger.info "slack-enhance-instanced"
    # TODO: Event APIを使わない場合、などのオプションをつける
    @web = @robot.adapter.client.web
    @self = @robot.adapter.client.rtm.dataStore.getUserByName @robot.name
    defaults =
      event: true
      interactive: true
      slash: true
    options = _.extend defaults, options
    @listen options

  @getInstance = do ->
    _instance = undefined
    flag = __from_get_instance: true
    (robot, options)->
      _instance ?= new Slack robot, _.extend options ? {}, flag

  @isSlackAdapter = (robot)->
    robot.adapter instanceof SlackBot

  emojideco: (message, name, repeat=1)->
    emo = _.repeat ":#{name}:", repeat
    "#{emo} #{message} #{emo}"

  generateAttachment: (color, extra={})->
    #timestamp = new Date/1000 | 0
    option =
      fallback: '<Attachment>'
      color: color
      #ts: timestamp
    _.extend option, extra

  generateFieldAttachment: (color, extra={})->
    extra.fields = []
    @generateAttachment color, extra

  generateActionAttachment: (color, callback_id, extra={})->
    extra.actions = []
    extra.callback_id = callback_id
    @generateAttachment color, extra

  generateField: (title, value, short=false)->
    option =
      title: title
      value: value
      short: short
    option

  generateButton: (name, value, style="default", extra={})->
    option =
      name: name
      text: name
      type: "button"
      value: value
      style: style
    _.extend option, extra

  generateConfirm: (title, text, ok, cancel, extra={})->
    option =
      title: title
      text: text
      ok_text: ok
      dismiss_text: cancel
    _.extend option, extra

  listenInteractive: ->
    unless process.env.HUBOT_SLACK_INTERACTIVE_ENDPOINT?
      @robot.logger.warning 'HUBOT_SLACK_INTERACTIVE_ENDPOINT is `/slack/interactive-endpoint` by default.'
    HUBOT_SLACK_INTERACTIVE_ENDPOINT = process.env.HUBOT_SLACK_INTERACTIVE_ENDPOINT or '/slack/interactive-endpoint'

    if @robot.router.routes.post?.some((p)-> p.path == HUBOT_SLACK_INTERACTIVE_ENDPOINT)
      @robot.logger.warning "POST: #{HUBOT_SLACK_INTERACTIVE_ENDPOINT} is already registered."
      return
    # interactive用
    @robot.router.post HUBOT_SLACK_INTERACTIVE_ENDPOINT, (req, res) =>
      content = JSON.parse req.body.payload
      # callback_idで呼び出す関数を変える
      func = Slack.actionListener[content.callback_id]
      # 存在しなければさようなら
      return unless func
      idx = parseInt(content.attachment_id) - 1
      orig = content.original_message
      ret = func content.user, content.actions[0], orig, content
      if ret
        # ボタンをクリック後に別のattachmentに置き変えるタイプ
        # originalの中身のうち、attachmentを変えたものを送るとうまくいく
        orig.attachments[idx] = ret
        res.json orig
        # お役御免
        delete Slack.actionListener[content.callback_id]
      else
        # ボタンクリックしたあとも残すタイプ
        res.end ""

  listenEvent: ->
    unless process.env.HUBOT_SLACK_EVENT_ENDPOINT?
      @robot.logger.warning 'HUBOT_SLACK_EVENT_ENDPOINT is `/slack/event-endpoint` by default.'
    HUBOT_SLACK_EVENT_ENDPOINT = process.env.HUBOT_SLACK_EVENT_ENDPOINT or '/slack/event-endpoint'

    if @robot.router.routes.post?.some((p)-> p.path == HUBOT_SLACK_EVENT_ENDPOINT)
      @robot.logger.warning "POST: #{HUBOT_SLACK_EVENT_ENDPOINT} is already registered."
      return
    # EventAPI用
    @robot.router.post HUBOT_SLACK_EVENT_ENDPOINT, (req, res) =>
      return unless req.body.token == process.env.HUBOT_SLACK_TOKEN_VERIFY
      if req.body.challenge?
        # Verify
        challenge = req.body.challenge
        return res.json challenge: challenge
      return unless req.body.event?

      ev = req.body.event
      @robot.logger.info "#{inspect ev, depth: null}"
      user = @robot.adapter.client.rtm.dataStore.getUserById ev.user
      item = ev.item
      channel = item.channel
      @emit ev.type, ev, user, channel, item
      res.end ''

  listenSlash: ->
    unless process.env.HUBOT_SLACK_SLASH_ENDPOINT?
      @robot.logger.warning 'HUBOT_SLACK_SLASH_ENDPOINT is `/slack/slash/:command` by default.'
    HUBOT_SLACK_SLASH_ENDPOINT = process.env.HUBOT_SLACK_SLASH_ENDPOINT or '/slack/slash/:command'

    if @robot.router.routes.post?.some((p)-> p.path == HUBOT_SLACK_SLASH_ENDPOINT)
      @robot.logger.warning "POST: #{HUBOT_SLACK_SLASH_ENDPOINT} is already registered."
      return

    @slash = new EventEmitter()
    @robot.router.post HUBOT_SLACK_SLASH_ENDPOINT, (req, res) =>
      return unless req.body.token == process.env.HUBOT_SLACK_TOKEN_VERIFY
      if req.body.challenge?
        # Verify
        challenge = req.body.challenge
        return res.json challenge: challenge

      option =
        text: req.body.text
        user:
          id: req.body.user_id
          name: req.body.user_name
        channel:
          id: req.body.channel_id
          name: req.body.channel_name
        command: req.body.command

      ret = @slash.emit req.params.command, option, (text, extra={})->
        options =
          text: text
          unfurl_links: true
          as_user: true
        options = _.extend options, extra
        res.json options

      res.end 'no such a command' unless ret

  listen: (options)->
    #console.log @robot.router.routes
    @listenInteractive() if options.interactive
    @listenEvent() if options.event
    @listenSlash() if options.slash

  interactiveMessagesListen: (callback_id, callback)->
    Slack.actionListener[callback_id] = callback

  generateChoice: (callback_id, color, buttons, option, callback)->
    timestamp = new Date().getTime()
    cid = "#{callback_id}_#{timestamp}"
    # ボタンクリック時の動作を登録
    @interactiveMessagesListen cid, callback
    # 送信するためのattachmentを作る
    at = @generateActionAttachment color, cid, option
    for btn in buttons
      at.actions.push @generateButton btn[0], btn[1], btn[2] ? "default"
    at

  say: (room, message, extra={}, cb=undefined)->
    if cb is undefined and typeof(extra) == "function"
      [cb, extra] = [extra, {}]
    options =
      unfurl_links: true
      as_user: true
    options = _.extend options, extra
    @web.chat.postMessage room, message, options, cb

  sendAttachment: (room, attachments, extra={}, cb=undefined)->
    if cb is undefined and typeof(extra) == "function"
      [cb, extra] = [extra, {}]
    options =
      as_user: true
      link_names: 1
      attachments: attachments
    options = _.extend options, extra
    @web.chat.postMessage room, '', options, cb

  addReaction: (reaction, room, ts)->
    @web.reactions.add reaction,
      timestamp: ts
      channel: room

  post: (method, param, cb)->
    options =
      form: param
    options.form.token = process.env.HUBOT_SLACK_APPS_TOKEN
    request.post "https://slack.com/api/#{method}", options, (err, res, body)=>
      return @robot.logger.error "#{inspect err}" if err
      return @robot.logger.error "#{inspect res}" if res.statusCode != 200
      json = JSON.parse body
      #@robot.logger.info "#{inspect json}"
      cb not json.ok, json

  getMethodByChannel: (channel, method)->
    pre = switch channel.charAt 0
      when 'D' then 'im'
      when 'C' then 'channels'
      when 'G' then 'groups'
      else 'channels'
    "#{pre}.#{method}"

  getMessageFromTimestamp: (channel, ts, cb)->
    options =
      channel: channel
      latest: ts
      oldest: ts
      inclusive: 1
      count: 1
    method = @getMethodByChannel channel, 'history'
    @post method, options, (err, res)=>
      if err
        @robot.logger.error "#{inspect res, depth: null}"
        return cb err, null
      msg = res.messages[0]
      @robot.logger.info "#{inspect msg, depth: null}"
      user = @robot.adapter.client.rtm.dataStore.getUserById msg.user
      msg.userName = user.name
      cb null, msg

  _deleteMessage: (channel, ts)->
    @web.chat.delete ts, channel

  deleteMessage: (channel, count, cb)->
    options =
      channel: channel
      count: count
    method = @getMethodByChannel channel, 'history'
    @post method, options, (err, res)=>
      return @robot.logger.error "#{inspect res, depth: null}" if err
      cnt = 0
      for msg in res.messages
        # as_userにしてないと、msg.bot_idになってしまう
        if msg.user?
          continue unless msg.user == @self.id
        else if msg.bot_id?
          continue unless msg.bot_id == @self.profile.bot_id
        else
          continue
        @_deleteMessage channel, msg.ts
        cnt += 1
      cb cnt if cb

module.exports = Slack
