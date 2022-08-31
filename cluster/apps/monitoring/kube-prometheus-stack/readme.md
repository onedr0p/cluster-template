# Notes

## To use Discord instead of Slack

The Slack webhooks are usable as `slack_api_url`.
However, for Discord, you need to append `/slack` to the webhook found on the Discord channel, so for example:

`https://discordapp.com/api/webhooks/{webhook.id}/{webhook.token}` becomes `https://discordapp.com/api/webhooks/{webhook.id}/{webhook.token}/slack`

## Testing

- Slack

```sh
curl -X POST --data-urlencode "payload={\"channel\": \"#prometheus\", \"username\": \"webhookbot\", \"text\": \"This is posted to #prometheus and comes from a bot named webhookbot.\", \"icon_emoji\": \":ghost:\"}" https://hooks.slack.com/services/<your-slack-webhook>
```

- Discord

```sh
curl -X POST --data-urlencode "payload={\"channel\": \"#prometheus\", \"username\": \"webhookbot\", \"text\": \"This is posted to #prometheus and comes from a bot named webhookbot.\", \"icon_emoji\": \":ghost:\"}" https://discordapp.com/api/webhooks/<your-discord-webhook>/slack
```
