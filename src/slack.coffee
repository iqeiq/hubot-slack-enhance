_ = require 'lodash'
SlackBot = require.main.require 'hubot-slack/src/bot'

class Slack
  constructor: (@robot, options={})->
    @actionListener = {}
    @listen()

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

  listen: ->
    # attachment用
    @robot.router.post "/slack/action", (req, res) =>
      content = JSON.parse req.body.payload
      # callback_idで呼び出す関数を変える
      func = @actionListener[content.callback_id]
      # 存在しなければさようなら
      return unless func
      # interactiveMessagesのtextフィールドを取り出す
      idx = parseInt content.attachment_id
      orig = content.original_message
      text = orig.attachments[idx - 1].text ? ""
      ret = func content.user, content.channel, content.actions[0], text, orig
      if ret
        # ボタンをクリック後に別のattachmentに置き変えるタイプ
        res.json ret
        # お役御免
        delete @actionListener[content.callback_id]
      else
        # ボタンクリックしたあとも残すタイプ
        res.end ""

    # EventAPI用
    @robot.router.post "/slack/event-endpoint", (req, res) =>
      return unless req.body.token == process.env.SLACK_TOKEN_VERIFY
      if req.body.challenge?
        challenge = req.body.challenge
        return res.json challenge: challenge
      return unless req.body.event?
      ev = req.body.event
      console.log ev
      user = @robot.adapter.client.rtm.dataStore.getUserById ev.user
      item = ev.item
      channel = item.channel
      switch ev.type
        when 'star_added', 'star_removed'
          link = item.message.permalink
          text = item.message.text
          method = ev.type.replace 'star_', ''
          @say channel, ":star: #{method} by #{user.name}: #{link}"
        when 'reaction_added', 'reaction_removed'
          break if user.name == @robot.name
          reaction = ev.reaction
          type = item.type
          ts = item.ts
          func = if ev.type == 'reaction_added' then 'add' else 'remove'
          if func == 'add'
            #@say channel, ":#{reaction}: added by #{user.name}"
            opt =
              latest: ts
              oldest: ts
            # missing_scopeが出てきて取れないんだけど？
            #@robot.adapter.client.web.channels.history channel, opt, (err, res)->
            #  console.log err if err
            #  console.log res if res
          @robot.adapter.client.web.reactions[func] reaction,
            timestamp: ts
            channel: channel
      res.end ''

  interactiveMessagesListen: (callback_id, callback)->
    @actionListener[callback_id] = callback

  generateChoice: (base, color, text, buttons, callback)->
    timestamp = new Date().getTime()
    cid = "#{base}_#{timestamp}"
    # ボタンクリック時の動作を登録
    @interactiveMessagesListen cid, callback
    # 送信するためのattachmentを作る
    at = @generateActionAttachment color, cid,
      text: text
    for btn in buttons
      at.actions.push @generateButton btn[0], btn[1], btn[2] ? "default"
    at

  say: (room, message, extra={})->
    options =
      unfurl_links: true
    options = _.extend options, extra
    @robot.adapter.client.web.chat.postMessage room, message, options

  sendAttachment: (room, attachments, extra={})->
    options =
      as_user: true
      link_names: 1
      attachments: attachments
    options = _.extend options, extra
    @robot.adapter.client.web.chat.postMessage room, '', options

  addReaction: (reaction, room, ts)->
    @robot.adapter.client.web.reactions.add reaction,
      timestamp: ts
      channel: room

module.exports = Slack
