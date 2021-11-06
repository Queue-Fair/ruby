# Copyright 2021 Matt King
# frozen_string_literal: true

# The Queue-Fair module
module QueueFair
  # QueueFairService encapsulates Rails-specific acctions on the HTTP Response.
  # If you are not using Rails, you will need to modify this class.
  class QueueFairService
    def initialize(action_controller, controller_cookies, requested_url)
      @controller = action_controller
      @cookies = controller_cookies
      @is_secure = false
      @sent_no_ache = false
      return if requested_url.nil?

      i = requested_url.index('https://')
      @is_secure = true if !i.nil? && i.zero?
    end

    def set_cookie(cname, value, lifetime_seconds, path, cookie_domain)
      no_cache
      cookie = { value: value, path: path, expires: Time.now + lifetime_seconds.to_i.second }
      cookie['domain'] = cookie_domain unless cookie_domain.nil?

      if @is_ecure
        cookie['secure'] = true
        cookie['same_site'] = 'None'
      end

      @cookies[cname] = cookie
    end

    def get_cookie(cname)
      @cookies[cname]
    end

    def no_cache
      return if @sent_no_cache

      @sent_no_cache = true
      @controller.response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0'
      @controller.response.headers['Pragma'] = 'no-cache'
      @controller.response.headers['Expires'] = 'Mon, 01 Jan 1990 00:00:00 GMT'
    end

    def add_header(hname, value)
      @controller.response.headers[hname] = value
    end

    def redirect(location)
      no_cache
      @controller.redirect_to location
    end

    def get_parameter(pname)
      @controller.params[pname]
    end
  end
end
