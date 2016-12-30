# hubot-slack-enhance
Add functions for hubot-slack

## TODO

* Incomming
* Slash Commands

## ENV

Env                               | Description                   | Required | Default
--------------------------------- | ----------------------------- | -------- | ---------------------------
`HUBOT_SLACK_VERIFY`              | use Event Subscriptions       | required | (empty)
`HUBOT_SLACK_EVENT_ENDPOINT`      | use Event Subscriptions       |          | `/slack/event-endpoint`
HUBOT_SLACK_SLASH_ENDPOINT`       | use Slash Commands            |          | `/slack/slash/:command`
`HUBOT_SLACK_INTERACTIVE_ENDPOINT` | use Interactive Messages      |          | `/slack/interactive-endpoint`
`HUBOT_SLACK_APPS_TOKEN`          | use APIs Apps-Bot cannot call | required | (empty)

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
