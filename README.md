# hubot-slack-enhance
Add functions for hubot-slack

## TODO

* Incomming
* Slash Commands

## ENV

* `HUBOT_SLACK_VERIFY`: required (when use Event Subscriptions)
* `HUBOT_SLACK_EVENT_ENDPOINT`: required (when use Event Subscriptions)
* `HUBOT_SLACK_ATTACHMENT_ENDPOINT`: required (when use Interactive Messages)


## Sample

```coffee
Slack = require 'hubot-slack-enhance'

module.exports = (robot)->
  return unless Slack.isSlackAdapter robot
  slack = new Slack robot
  
  robot.hear /apple/i, (res)->
    mes = res.envelope.message
    slack.addReaction 'apple', mes.room, mes.id
  
  slack.on 'star_added', (ev, user, channel, item)->
    return if user.name == robot.name
    link = item.message.permalink
    slack.say channel, ":star: added by #{user.name}: #{link}"

```
