#!/usr/bin/env ruby

require 'optparse'
require "selenium-webdriver"
require 'yaml'

# Simplistic command line parsing.
params = ARGV.getopts("", "debug", "username:", "password:", "reckonargs:")
raise "Must provide --username." unless params["username"]
raise "Must provide --password." unless params["password"]
raise "Must provide --reckonargs." unless params["reckonargs"]
DEBUG = !!params["debug"]


capabilities = Selenium::WebDriver::Remote::Capabilities.phantomjs("phantomjs.page.settings.userAgent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36")
driver = Selenium::WebDriver.for :phantomjs, :desired_capabilities => capabilities

def otp(driver)
  wait = Selenium::WebDriver::Wait.new(:timeout => 30)

  driver.find_elements(:xpath, "//div[text() = 'Next']").each do |b|
    b.click if b.displayed?
  end

  xpath = "//fieldset[./legend[@data-attr='LOGON_IDENTIFICATION.requestIdentificationCodeEmailLabel']]//input"
  wait.until{ driver.find_element(:xpath, xpath) }
  driver.find_element(:xpath, xpath).click

  wait.until{ driver.find_element(:xpath, "//div[text() = 'Next']") }
  driver.find_elements(:xpath, "//div[text() = 'Next']").each do |b|
    b.click if b.displayed?
  end

  puts "Chase will now *email* an OTP token (a number). This is required"
  puts "because you are running this script for the first time and they"
  puts "are trying to make sure this is actually you. Please find the email"
  puts "and enter the token here, just the numbers, nothing else, then hit"
  puts "return."
  puts
  print "OTP token: "

  input = gets.strip
  wait.until{ driver.find_element(:id, "otpcode_input-input-field") }
  driver.find_element(:id, 'otpcode_input-input-field').send_keys(input)
  driver.find_element(:id, 'password_input-input-field').send_keys(params["password"])

  wait.until{ driver.find_element(:xpath, "//div[text() = 'Next']") }
  driver.find_elements(:xpath, "//div[text() = 'Next']").each do |b|
    b.click if b.displayed?
  end
end

begin
  # The window must be fairly large as we implemented this for the non-mobile
  # version of the chase website.
  driver.manage.window.resize_to(1000, 800)
  driver.navigate.to "https://secure01c.chase.com/web/auth/dashboard#/dashboard/index/index"

  # Prepare a default waiter.
  wait = Selenium::WebDriver::Wait.new(:timeout => 30)
  wait.until { driver.find_element(:id, 'logonbox') }

  # Switch to the login frame
  driver.switch_to.frame "logonbox"
  wait.until { driver.find_element(:id, 'userId-input-field') }

  # Log in
  user_element = driver.find_element(:id, 'userId-input-field')
  user_element.send_keys(params["username"])
  pass_element = driver.find_element(:id, 'password-input-field')
  pass_element.send_keys(params["password"])
  element = driver.find_element(:id, 'signin-button')
  driver.save_screenshot('s1.png') if DEBUG
  element.click
  driver.switch_to.default_content

  # Arbitrate between two possible outcomes. Either we see a next button and
  # have to handle the OTP code or we are ok and just proceed to downloading.
  while true
    if driver.find_elements(:id, 'logonbox').length > 0 then
      driver.switch_to.frame "logonbox"
      if driver.find_elements(:xpath, "//div[text() = 'Next']").length > 0
        otp(driver)
        break
      end
    end

    driver.switch_to.default_content
    if driver.find_elements(:class, 'account').length > 0 then
      break
    end
    sleep 1
  end

  driver.save_screenshot('s2.png') if DEBUG

  # Enumerate *real* accounts.
  wait.until { driver.find_element(:class, 'account') }
  accounts = driver.find_elements(:xpath, '//*[contains(@data-attr, "CREDIT_CARD_ACCOUNT.requestAccountInformation")]')
  driver.save_screenshot('s2.png')
  accounts.each do |a|
    balance = a.find_elements(:xpath, './/*[@data-attr="CREDIT_CARD_ACCOUNT.accountCurrentBalance"]').first.attribute("innerHTML")
    number = a.attribute("id").gsub("tile-", "").to_i
    raise "Number looks invalid: #{number} #{a.attribute("id")}" unless number > 0

    driver.save_screenshot('s3.png') if DEBUG

    script = <<-EOF
    var out;
    $.ajax({
      'async': false,
      'url': 'https://secure01c.chase.com/svc/rr/accounts/secure/v1/account/activity/download/card/list',
      'method': 'post',
      'data': { filterTranType: 'ALL', statementPeriodId: 'ALL', downloadType: 'CSV', accountId: '#{number}' },
      'success' : function(data, status, xhr) { out = data; }
    });
    return out;
    EOF
    puts script if DEBUG
    csv = driver.execute_script(script);
    next if !csv or csv.split("\n").size <= 1

    File.write("/tmp/debug", csv) if DEBUG
    file = Tempfile.new('csv')
    file.write(csv)
    file.close
    puts "reckon -f #{file.path} #{params["reckonargs"]}" if DEBUG
    puts `reckon -f #{file.path} #{params["reckonargs"]} | grep -v "I didn't find a high-likelyhood money column" | perl -pe 's/(\\d+\\/\\d+\\/\\d+)/$1 */g' | ledger -f - print`
    puts
    puts "#{Time.now.strftime("%Y/%m/%d")} * Assertion after sync."
    puts "    [Liabilities:Chase]  = -#{balance}"
    puts
    puts
    puts
  end

rescue => e
  puts "Error during processing: #{$!}"
  puts "Backtrace:\n\t#{e.backtrace.join("\n")}"
ensure
  driver.quit
end
