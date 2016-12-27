# hubot-slack-enhance
Add functions for hubot-slack

```coffee
Slack = require 'hubot-slack-enhance'
SlackBot = require 'hubot-slack/src/bot'

module.exports = (robot)->
  return unless robot.adapter instanceof SlackBot
  slack = new Slack robot
  # ...
  
  robot.hear /apple/i, (res)->
    mes = res.envelope.message
    slack.addReaction 'apple', mes.room, mes.id
  
  # ...
```
