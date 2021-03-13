require 'slack/incoming/webhooks'
require 'uri'

def scrapbox_diary_url(time)
  URI.parse('https://scrapbox.io').tap do |uri|
    uri.path = '/tanaken0515/' + time.strftime('%F')
    uri.query = URI.encode_www_form({
      body: %w[%Y-%m %Y年%m月 %m-%d %m月%d日].map{ |format| '#' + time.strftime(format) }.join(' ')
    })
  end.to_s
end

slack = Slack::Incoming::Webhooks.new(ENV['SLACK_WEBHOOK_URL'])
jst_now = Time.now.localtime('+09:00')
slack.post(scrapbox_diary_url(jst_now))
