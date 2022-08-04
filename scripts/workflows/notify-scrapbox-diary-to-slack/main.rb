require 'holiday_jp'
require 'slack/incoming/webhooks'
require 'uri'

def scrapbox_diary_url(date)
  tags = %w[%Y-%m %Y年%m月 %m-%d %m月%d日 %Y-%m-%d %Y年%m月%d日].map{ |format| date.strftime(format) }

  tags += ['祝日', holiday_name(date)] if holiday_name(date)

  body = <<~EOS
    #{tags.map{ |tag| '#' + tag }.join(' ')}
    
    [** あったこと、おもったこと]

    [** たべたもの、のんだもの]

  EOS
  URI.parse('https://scrapbox.io').tap do |uri|
    uri.path = '/tanaken0515/' + date.strftime('%F')
    uri.query = URI.encode_www_form({
      body: body
    })
  end.to_s
end

def holiday_name(date)
  HolidayJp.between(date, date).first&.name
end

jst_now = Time.now.localtime('+09:00')
today = Date.new(jst_now.year, jst_now.month, jst_now.day)

slack = Slack::Incoming::Webhooks.new(ENV['SLACK_WEBHOOK_URL'])
slack.post("<#{scrapbox_diary_url(today)}|#{today.strftime('%F %a')}>")
