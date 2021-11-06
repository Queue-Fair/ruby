# frozen_string_literal: true

require 'queue_fair/queue_fair'

class ExampleController < ApplicationController
  def index
    QueueFair::QueueFairConfig.account = 'ACCOUNT_SYSTEM_NAME_FROM_PORTAL'
    QueueFair::QueueFairConfig.account_secret = 'ACCOUNT_SECRET_FROM_PORTAL'

    # Comment out the below line for production environments.
    QueueFair::QueueFairConfig.debug = true

    # If you are not using Rails, you will need to modify queue_fair_service.rb
    service = QueueFair::QueueFairService.new(self, cookies, request.url)

    # The Adapter object.
    adapter = QueueFair::QueueFairAdapter.new(service)

    # If your web server is behind a CDN or proxy, you may need to edit these.
    adapter.requested_url = request.url
    adapter.query = request.query_string
    adapter.remote_addr = request.remote_ip
    adapter.user_agent = request.user_agent

    # If you just want to validate a cookie, use the below.
=begin
    if request.url.index('/path/to/protected/page') !=nil
      begin
        passed_lifetime_minutes = 60
        queue_name='QUEUE_SYSTEM_NAME_FROM_PORTAL'
        if(!adapter.validate_cookie('QUEUE_SECRET_FROM_PORTAL',
          passed_lifetime_minutes, cookies['QueueFair-Pass-'+queue_name]))
          adapter.redirect('https://'+QueueFair::QueueFairConfig.account+".queue-fair.net/"+queue_name+"?qfError=InvalidCookie",0)
          return
        end
      rescue StandardError => e
        puts "ERROR #{e}"
        e.backtrace
      end
    end
=end

    # Otherwise, run the full adapter process.
    return nil unless adapter.go

    # Rest of controller index function continues here.
  end
end
