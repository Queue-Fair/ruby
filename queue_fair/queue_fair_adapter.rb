# Copyright 2021 Matt King
# frozen_string_literal: true

# rubocop:disable Style/ClassVars
# rubocop:disable Metrics/CyclomaticComplexity
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/PerceivedComplexity
# rubocop:disable Lint/NonLocalExitFromIterator
require 'json'
require 'net/http'

# The Queue-Fair Module
module QueueFair
  # The Queue-Fair Adapter class.
  class QueueFairAdapter
    # For the settings cache
    @@cache = nil
    @@mem_settings = nil
    @@last_cache_store = nil

    # Constants
    PROTOCOL = 'https'
    COOKIE_NAME_BASE = 'QueueFair-Pass-'

    attr_accessor :requested_url, :query, :remote_addr, :user_agent, :extra

    def initialize(queue_fair_service)
      @service = queue_fair_service
      @requested_url = ''
      @query = ''
      @remote_addr = ''
      @user_agent = ''
      @continue_page = true
      @settings = nil
      @extra = nil
    end

    def set_uid_from_cookie
      cookie_base = "QueueFair-Store#{QueueFairConfig.account}"
      cookie = @service.get_cookie(cookie_base)
      if cookie.nil?
        @uid = nil
        return
      end
      i = cookie.index ':'
      i = cookie.index '=' if i.nil?
      return if i.nil?

      @uid = cookie[i + 1..]
      log "Found UID #{@uid}" if @d
    end

    def key(map, key)
      map.key?(key)
    end

    def check_query_string
      return if query.nil?

      q = query.rindex 'qfqid='

      return if q.nil?

      log 'Passed string found' if @d

      i = query.rindex 'qfq='

      return if i.nil?

      log 'Passed string with queue name found' if @d

      j = query.index '&', i
      sub_start = i + 'qfq='.length
      queue_name = query[sub_start..j - 1]
      log "Queue name is #{queue_name}" if @d

      @settings['queues'].each do |queue|
        next if queue['name'] != queue_name

        log "Found queue for querystring #{queue_name}" if @d

        value = query[query.rindex('qfqid')..]

        unless validate_query queue
          queue_cookie = get_cookie COOKIE_NAME_BASE + queue_name
          if !queue_cookie.nil? && queue_cookie != ''
            log "Query validation failed but we have a cookie #{queue_cookie}" if @d
            return if validate_cookie_queue queue, queue_cookie

            log 'Query AND Cookie validation failed !!!' if @d
          elsif @d
            log "Bad queue_cookie for #{queue_name} #{queue_cookie}"
          end
          log 'Query validation failed - redirecting to error page.' if @d

          redirect("#{PROTOCOL}://#{queue['queueServer']}/#{queue['name']}?qfError=InvalidQuery", 0)
          return
        end
        log "Query validation succeeeded for #{value}" if @d
        @passed_string = value
        set_queue_cookie(queue_name, value, queue['passedLifetimeMinutes'] * 60,
                         key(queue, 'cookieDomain') ? queue['cookieDomain'] : nil)

        return unless @continue_page

        log "Marking #{queue_name} as passed by queryString" if @d
        mark_passed queue_name
      end
    end

    def redirect(where, slp)
      sleep slp if slp.positive?
      @continue_page = false
      @service.redirect(where)
    end

    def mark_passed(_queue_name)
      @passed_queues = {} if @passed_queues.nil?
      @passed_queues['queue_name'] = true
    end

    def passed(queue)
      @passed_queues = {} if @passed_queues.nil?
      if key @passed_queues, queue['name']
        log "Queue #{queue['name']} marked as passed already" if @d
        return true
      end
      queue_cookie = get_cookie(COOKIE_NAME_BASE + queue['name'])
      if queue_cookie.nil?
        log "No cookie found for queue #{queue['name']}" if @d
        return false
      end
      if queue_cookie.index(queue['name']).nil?
        log "Cookie value is invalid for  #{queue['name']}" if @d
        return false
      end

      unless validate_cookie_queue(queue, queue_cookie)
        log "Cookie failed validation #{queue_cookie}" if @d
        set_queue_cookie(queue['name'], '', 0, queue['cookieDomain'])
        return false
      end

      log "Found valid cookie for #{queue['name']}" if @d
      true
    end

    def validate_cookie_queue(queue, cookie)
      validate_cookie_intern queue['secret'], queue['passedLifetimeMinutes'], cookie
    end

    def validate_cookie(queue_secret, passed_lifetime_minutes, cookie)
      set_debug
      validate_cookie_intern(queue_secret, passed_lifetime_minutes, cookie)
    end

    def validate_cookie_intern(queue_secret, passed_lifetime_minutes, cookie)
      log "Validating cookie #{cookie}" if @d
      return false if cookie.nil?

      begin
        parsed = CGI.parse(cookie)
        ghash = parsed['qfh'][0]
        return false if ghash.nil?

        hpos = cookie.rindex('qfh=')
        check = cookie[0..hpos - 1]

        check_hash = create_hash(queue_secret, process_identifier(@user_agent) + check)

        if ghash != check_hash
          log "Cookie Hash Mismatch Given #{ghash} Should be #{check_hash}" if @d
          return false
        end

        tspos = parsed['qfts'][0].to_i
        if tspos < Time.now.to_i - (passed_lifetime_minutes.to_i * 60)
          log "Cookie timestamp too old #{Time.now.to_i - tspos}" if @d
          return false
        end

        log 'Cookie Validated ' if @d
        return true
      rescue StandardError => e
        log "Cookie validation failed with error #{e}"
      end
      false
    end

    def validate_query(queue)
      begin
        str = @query
        q = CGI.parse(str)

        log "Validating Passed Query #{@query}" if @d

        hpos = str.rindex('qfh=')
        if hpos.nil?
          log 'No Hash In Query' if @d
          return false
        end

        query_hash = q['qfh'][0]

        if query_hash.nil?
          log 'Malformed hash' if @d
          return false
        end

        qpos = str.rindex('qfqid=')

        if qpos.nil?
          log 'No Queue Identifier' if @d
          return false
        end

        # query_qid = q['qfqid'][0]
        query_ts = q['qfts'][0]

        # query_account = q['qfa'][0]
        # query_queue = q['qfq'][0]

        # query_pass_type = q['qfpt'][0]

        if query_ts.nil?
          log 'No Timestamp' if @d
          return false
        end

        query_ts = query_ts.to_i
        unless query_ts.is_a? Numeric
          log 'Timestamp Not Numeric' if @d
          return false
        end

        if query_ts > (Time.now.to_i + QueueFairConfig.query_time_limit_seconds).to_i
          log "Too Late #{query_ts} #{Time.now}" if @d
          return false
        end

        if query_ts < (Time.now.to_i - QueueFairConfig.query_time_limit_seconds).to_i
          log "Too Early #{query_ts} #{Time.now}" if @d
          return false
        end

        check = str[qpos..hpos - 1]

        check_hash = create_hash(queue['secret'], process_identifier(@user_agent) + check)

        if check_hash != query_hash
          log 'Failed Hash' if @d
          return false
        end

        return true
      rescue StandardError => e
        log "Query validation failed with error #{e}"
      end
      false
    end

    def create_hash(key, data)
      digest = OpenSSL::Digest.new('sha256')
      OpenSSL::HMAC.hexdigest(digest, key, data)
    end

    def set_queue_cookie(queue_name, value, lifetime_seconds, cookie_domain)
      set_cookie "QueueFair-Pass-#{queue_name}", value, lifetime_seconds, '/', cookie_domain
      return if lifetime_seconds.to_i.zero?

      mark_passed(queue_name)
      return unless QueueFairConfig.strip_passed_string

      pos = @requested_url.index('qfqid=')
      return if pos.nil?

      loc = @requested_url[0..pos - 1]
      redirect(loc, 0)
    end

    def set_cookie(cname, value, lifetime_seconds, path, cookie_domain)
      log "Setting cookie for #{cname} to #{value} on #{cookie_domain}" if @d
      @service.set_cookie(cname, value, lifetime_seconds, path, cookie_domain)
    end

    def get_cookie(cname)
      @service.get_cookie(cname)
    end

    def parse_settings
      queues = @settings['queues']
      if queues.length.zero?
        log 'No queues found.' if @d
        return
      end

      log 'Running through queue rules.' if @d

      queues.each do |queue|
        if passed queue
          log "Queue #{queue['name']} already passed." if @d
          next
        end

        log "Checking #{queue['displayName']}" if @d

        if match queue
          unless on_match queue
            return unless @continue_page

            log "Found matching unpassed queue #{queue['displayName']}" if @d
            return nil unless QueueFairConfig.adapter_mode == 'safe'

            next
          end
          return unless @continue_page

          mark_passed queue['name']
        elsif @d
          log "Rules did not match #{queue['displayName']}"
        end
      end

      log 'All queues checked.' if @d
    end

    def match(queue)
      return false if queue.nil?
      return false unless key(queue, 'activation')

      activation = queue['activation']
      return false unless key(activation, 'rules')

      match_array(activation['rules'])
    end

    def match_array(rules)
      return false if rules.nil?

      first_op = true
      state = false

      i = 0
      rules.each do |rule|
        i += 1
        if !first_op && key(rule, 'operator')
          # rubocop:disable Style/GuardClause
          if rule['operator'] == 'And' && !state
            return false
          elsif rule['operator'] == 'Or' && state
            return true
          end
          # rubocop:enable Style/GuardClause
        end
        rm = rule_match rule

        if first_op
          state = rm
          first_op = false
          if @d then log "  Rule 1: #{rm ? 'true' : 'false'}" end
        else
          if @d then log "  Rule #{i + 1}: #{rm ? 'true' : 'false'}" end
          case rule['operator']
          when 'And'
            state &&= rm
            break unless state
          when 'Or'
            state ||= rm
            break if state
          end
        end
      end

      if @d then log "Final result is #{state ? 'true' : 'false'}" end
      state
    end

    def rule_match(rule)
      comp = extract_component rule, @requested_url, key(rule, 'name') ? get_cookie(rule['name']) : nil
      rule_match_with_value rule, comp
    end

    def rule_match_with_value(rule, comp)
      t = rule['value']

      unless rule['caseSensitive']
        comp = comp.downcase
        t = t.downcase
      end

      log "  Testing #{rule['component']} #{t} against #{comp}" if @d

      ret = false

      if rule['match'] == 'Equal' && comp == t
        ret = true
      elsif rule['match'] == 'Contain' && !comp.nil? && comp != '' && !comp.index(t).nil?
        ret = true
      elsif rule['match'] == 'Exist'
        ret = if [nil, ''].include?(comp)
                false
              else
                true
              end
      end

      ret = !ret if rule['negate']
      ret
    end

    def extract_component(rule, url, cookie_value)
      comp = url.to_s
      case rule['component']
      when 'Domain'
        comp = URI.parse(url).host
      when 'Path'
        domain = comp.gsub('http://', '')
        domain.gsub!('https://', '')
        domain = domain.split("/[\/\?#:]/") [0]
        comp = comp[(comp.index(domain) + domain.length)..]

        i = comp.index(':')
        if !i.nil? && i.zero?
          i = comp.index '/'
          comp = if !i.nil?
                   comp[i..]
                 else
                   ''
                 end
        end

        i = comp.index('#')
        comp = comp[0..i - 1] unless i.nil?

        i = comp.index('?')
        comp = comp[0..i - 1] unless i.nil?
        comp = '/' if comp == ''
      when 'Query'
        comp = if comp.index('?').nil?
                 ''
               elsif comp == '?'
                 ''
               else
                 comp[(comp.index('?') + 1)..]
               end
      when 'Cookie'
        comp = cookie_value
      end
      comp
    end

    def on_match(queue)
      if passed queue
        log "Already passed #{queue['name']}." if @d
        return true
      elsif !@continue_page
        return false
      end

      log "Checking at server #{queue['displayName']}" if @d
      consult_adapter(queue)
      false
    end

    def consult_adapter(queue)
      @adapter_queue = queue
      adapter_mode = QueueFairConfig.adapter_mode

      adapter_mode = queue['adapter_mode'] if key(queue, 'adapter_mode')

      log "Adapter mode is #{adapter_mode}" if @d
      if adapter_mode == 'safe'
        url = "#{PROTOCOL}://#{queue['adapterServer']}/adapter/#{queue['name']}"
        url += "?ipaddress=#{CGI.escape(@remote_addr)}"

        url += "&uid=#{uid}" unless @uid.nil?

        url += "&identifier=#{CGI.escape(process_identifier(@user_agent))}"

        log "Adapter URL #{url}" if @d

        json = load_url(url)

        if json.nil?
          log 'No Adapter JSON!'
          return
        end

        log "Downloaded JSON#{json}" if @d

        @adapter_result = json
        got_adapter
        nil unless @continue_page

      else
        url = "#{PROTOCOL}://#{queue['queueServer']}/#{queue['name']}?target=#{CGI.escape(@requested_url)}"
        url = append_variant(queue, url)
        url = append_extra(queue, url)
        log "Redirecting to adapter server #{url}" if @d
        redirect(url, 0)
      end
    end

    def got_adapter
      log 'Got adapter' if @d
      if @adapter_result.nil?
        log 'ERROR: got_adapter called without result' if @d
        return
      end

      if key(@adapter_result, 'uid')
        if !@uid.nil? && @uid != @adapter_result['uid']
          log 'ERROR UID Cookie Mismatch - Contact Queue-Fair Support! expected '
          "#{+ @uid} but received #{@adapter_result['uid']}"
        else
          @uid = @adapter_result['uid']
          set_cookie(
            "QueueFair-Store-#{QueueFairConfig.account}",
            "u:#{@uid}",
            @adapter_result['cookieSeconds'].to_i,
            '/',
            @adapter_queue['cookieDomain']
          )
        end
      end

      unless key(@adapter_result, 'action')
        log 'ERROR: onAdapter() called without result action' if @d
        return
      end

      if @adapter_result['action'] == 'SendToQueue'
        log 'Sending to queue server.' if @d

        query_params = ''
        win_loc = @requested_url
        if @adapter_queue['dynamicTarget'] != 'disabled'
          query_params += 'target='
          query_params += CGI.escape(win_loc)
        end

        unless @uid.nil?
          query_params += '&' if query_params != ''

          query_params += "qfuid=#{@uid}"
        end

        redirect_loc = @adapter_result['location']
        redirect_loc = "#{redirect_loc}?#{query_params}" if query_params != ''

        redirect_loc = append_variant(@adapter_queue, redirect_loc)
        redirect_loc = append_extra(@adapter_queue, redirect_loc)
        log "Redirecting to #{redirect_loc}" if @d

        redirect(redirect_loc, 0)
        return
      end

      # SafeGuard etc
      set_queue_cookie(@adapter_result['queue'], CGI.unescape(@adapter_result['validation']),
                       @adapter_queue['passedLifetimeMinutes'].to_i * 60,
                       @adapter_queue['cookieDomain'])

      return unless @continue_page

      log "Marking #{@adapter_result['queue']} as passed by adapter." if @d

      mark_passed(@adapter_result['queue'])
    end

    def get_variant(queue)
      log "Getting variants for #{queue['name']}" if @d

      return nil unless key(queue, 'activation')

      return nil unless key(queue['activation'], 'variantRules')

      variant_rules = queue['activation']['variantRules']

      log "Checking variant rules for #{queue['name']}" if @d

      variant_rules.each do |variant|
        variant_name = variant['variant']
        rules = variant['rules']
        ret = match_array(rules)
        log "Variant match #{variant_name} #{ret}" if @d

        return variant_name if ret
      end

      nil
    end

    def process_identifier(parameter)
      return nil if parameter.nil?

      i = parameter.index('[')
      return parameter if i.nil?
      return parameter if i < 20

      parameter[0..i - 1]
    end

    def append_variant(queue, redirect_loc)
      log 'Looking for variant' if @d
      variant = get_variant(queue)
      if variant.nil?
        log 'No variant found' if @d
        return redirect_loc
      end

      log "Found variant #{variant}" if @d

      redirect_loc += if !redirect_loc.index('?').nil?
                        '&'
                      else
                        '?'
                      end

      redirect_loc += "qfv=#{CGI.escape(variant)}"
      redirect_loc
    end

    def append_extra(_queue, redirect_loc)
      return redirect_loc if @extra == '' || @extra.nil?

      log "Found extra #{extra}" if @d

      redirect_loc += if !redirect_loc.index('?').nil?
                        '&'
                      else
                        '?'
                      end

      redirect_loc += "qfx=#{CGI.escape(variant)}"
      redirect_loc
    end

    def got_settings
      check_query_string
      return unless @continue_page

      parse_settings
    end

    def retrieve_settings_from_cache
      t_store = @@cache.read 'QFLast_store'
      t_settings = @@cache.read 'QFSettings'
      if !t_settings.nil? && !t_store.nil? &&
         Time.new - t_store < QueueFairConfig.settings_file_cache_lifetime_minutes * 60
        @@mem_settings = JSON.parse t_settings
        @@last_cache_store = t_store
        log "Using cached settings #{@@mem_settings}" if @d
        return true
      end
      false
    end

    def load_url(source)
      begin
        url = URI.parse source
        req = Net::HTTP::Get.new url
        res = Net::HTTP.start url.host, url.port, use_ssl: url.scheme == 'https',
                                                  open_timeout: QueueFairConfig.read_timeout,
                                                  read_timeout: QueueFairConfig.read_timeout do |http|
          res = http.request req
        end
        data = res.body
        json = JSON.parse data
        return json
      rescue StandardError => e
        log "LOAD ERROR #{e}"
      end
      nil
    end

    def load_settings
      # log("Mem "+@@last_cache_store.to_s+": "+@@mem_settings.to_s+" "+(Time.new - @@last_cache_store).to_s)
      if !@@mem_settings.nil? && !@@last_cache_store.nil? &&
         Time.new - @@last_cache_store < QueueFairConfig.settings_file_cache_lifetime_minutes * 60
        log "Using memory cached settings #{@@mem_settings}" if @d
        return
      end

      # Create cache if it does not exist.
      if @@cache.nil?
        @@cache = ActiveSupport::Cache::FileStore.new QueueFairConfig.settings_file_cache_location,
                                                      expires_in: (
                                                        QueueFairConfig.settings_file_cache_lifetime_minutes
                                                        + 2).minutes
        log "Created Cache #{@@cache}" if @d
      end

      return if retrieve_settings_from_cache

      # Is another process already loading settings?
      i = 0
      locked = false
      while @@cache.read 'QFLock' == 'Locked' && i < QueueFairConfig.read_timeout
        log "Sleeping #{i}"
        locked = true
        i += 1
        sleep 1
      end

      return if locked && retrieve_settings_from_cache

      @@cache.write 'QFLock', 'Locked'

      source = "#{PROTOCOL}://#{QueueFairConfig.files_server}/#{QueueFairConfig.account}"
      source += "/#{QueueFairConfig.account_secret}/queue-fair-settings.json"
      json = load_url(source)

      unless json.nil?
        log "Downloaded settings #{json}" if @d
        @@mem_settings = json
        @@last_cache_store = Time.new
        @@cache.write 'QFSettings', json.to_json
        #				@@mem_settings = JSON.parse(@@cache.read("QFSettings"))
        @@cache.write 'QFLast_store', @@last_cache_store
      end
      @@cache.write 'QFLock', 'Unlocked'
    end

    def set_debug
      @d = QueueFairConfig.debug
      @d = if @d == @remote_addr || @d == true
             true
           else
             false
           end
    end

    def go
      begin
        set_debug
        log "Starting Adapter account: #{QueueFairConfig.account}" if @d
        set_uid_from_cookie
        load_settings
        if @@mem_settings.nil?
          log 'ERROR: No settings.'
          return
        end
        @settings = @@mem_settings
        got_settings
        log "Adapter finished. Continue page: #{@continue_page}" if @d
        return @continue_page
      rescue StandardError => e
        log "ERROR #{e}"
        # puts e.backtrace
      end
      true
    end

    def log(input)
      puts "QF #{input}"
    end
  end
end
# rubocop:enable Style/ClassVars
# rubocop:enable Metrics/CyclomaticComplexity
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Lint/NonLocalExitFromIterator
