# Copyright 2021 Matt King
# rubocop:disable Style/ClassVars
# frozen_string_literal: true

# The Queue-Fair module
module QueueFair
  # QueueFairConfig contains configuration settings for the Adapter.
  class QueueFairConfig
    # Your Account Secret is shown on the Your Account page of
    # the Queue-Fair Portal.  If you change it there, you must
    # change it here too.
    cattr_accessor :account_secret
    @@account_secret = 'DELETE THIS TEXT AND REPLACE WITH YOUR ACCOUNT SECRET'

    # The System Name of your account from the Your Account page
    # of the Queue-Fair Portal.
    cattr_accessor :account
    @@account = 'DELETE THIS TEXT AND REPLACE WITH YOUR ACCOUNT SYSTEM NAME'

    # Leave this set as is
    cattr_accessor :files_server
    @@files_server = 'files.queue-fair.net'

    # Time limit for Passed Strings to be considered valid,
    # before and after the current time
    cattr_accessor :query_time_limit_seconds
    @@query_time_limit_seconds = 30

    # Valid values are true, false, or an "IP_address".
    cattr_accessor :debug
    @@debug = false

    # How long to wait in seconds for network reads of config
    # or Adapter Server (safe mode only)
    cattr_accessor :read_timeout
    @@read_timeout = 5

    # You must set this to a folder that has write permission for your web server
    # If it's not saving as expected turn on debugging above and look for messages in
    # your Ruby logs.  On Unix use chmod -R 777 FOLDER_NAME
    # on the desired folder to enable Adapter writes, reads and access to folder contents.
    # For optimum performance, use a Ramdisk for this path.
    cattr_accessor :settings_file_cache_location
    @@settings_file_cache_location = './QFCache'

    # How long a cached copy of your Queue-Fair settings will be kept before downloading
    # a fresh copy.  Set this to 0 if you are updating your settings in the
    # Queue-Fair Portal and want to test your changes quickly, but remember
    # to set it back again when you are finished to reduce load on your server.
    cattr_accessor :settings_file_cache_lifetime_minutes
    @@settings_file_cache_lifetime_minutes = 5

    # Whether or not to strip the Passed String from the URL
    # that the Visitor sees on return from the Queue or Adapter servers
    # (simple mode) - when set to true causes one additinal HTTP request
    # to your site but only on the first matching visit from a particular
    # visitor. The recommended value is true.
    cattr_accessor :strip_passed_string
    @@strip_passed_string = true

    # Whether to send the visitor to the Adapter server for counting (simple mode),
    # or consult the Adapter server (safe mode).  The recommended value is "safe".
    cattr_accessor :adapter_mode
    @@adapter_mode = 'safe'
  end
end
# rubocop:enable Style/ClassVars
