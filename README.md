---
## Queue-Fair Ruby Adapter README & Installation Guide

Queue-Fair can be added to any web server easily in minutes.  You will need a Queue-Fair account - please visit https://queue-fair.com/free-trial if you don't already have one.  You should also have received our Technical Guide.

## Client-Side JavaScript Adapter

Most of our customers prefer to use the Client-Side JavaScript Adapter, which is suitable for all sites that wish solely to protect against overload.

To add the Queue-Fair Client-Side JavaScript Adapter to your web server, you don't need the Ruby files included in this extension.

Instead, add the following tag to the `<head>` section of your pages:
 
```
<script data-queue-fair-client="CLIENT_NAME" src="https://files.queue-fair.net/queue-fair-adapter.js"></script>`
```

Replace CLIENT_NAME with the account system name visibile on the Account -> Your Account page of the Queue-Fair Portal

You shoud now see the Adapter tag when you perform View Source after refreshing your pages.

And you're done!  Your queues and activation rules can now be configured in the Queue-Fair Portal.

## Server-Side Adapter

The Server-Side Adapter means that your web server communicates directly with the Queue-Fair servers, rather than your visitors' browsers.

This can introduce a dependency between our systems, which is why most customers prefer the Client-Side Adapter.  See Section 10 of the Technical Guide for help regarding which integration method is most suitable for you.

The Server-Side Adapter is a small Ruby library that will run when visitors access your site.  It periodically checks to see if you have changed your Queue-Fair settings in the Portal, but other than that if the visitor is requesting a page that does not match any queue's Activation Rules, it does nothing.

If a visitor requests a page that DOES match any queue's Activation Rules, the Adapter consults the Queue-Fair Queue Servers to make a determination whether that particular visitor should be queued.  If so, the visitor is sent to our Queue Servers and execution and generation of the page for that HTTP request for that visitor will cease.  If the Adapter determines that the visitor should not be queued, it sets a cookie to indicate that the visitor has been processed and your page executes and shows as normal.

Thus the Server-Side Adapter prevents visitors from skipping the queue by disabling the Client-Side JavaScript Adapter, and also reduces load on your web server when things get busy.

These instructions assume you already have a Ruby on Rails webapp.  If you are setting up Ruby on Rails for the first time, follow the turtorial at https://guides.rubyonrails.org/getting_started.html 

If you are not using Rails, you can still use the example code in `example_controller.rb` from this distribution - but you will also need to implement your own QueueFairService class to encapsulate your alternative HTTP framework.  It's only four basic methods to write.

Here's how to install the adapter in your existing Rails webapp.

**1.** Copy the queue_fair folder from this distribution into the /lib folder of your framework.


**2.** By default, Queue-Fair will cache your account settings in the top level folder of your webapp, in a subfolder called QFCache.  If you want the cache to reside elsewhere, do

```
    sudo mkdir /opt/qfsettings    
    sudo chmod 777 /opt/qfsettings
```
and then set QueueFairConfig.settings_file_cache_location to match.

Note: The settings folder can go anywhere, but for maximum security this should not be in your web root.  The executable permission is needed on the folder so that the Adapter can examine its contents.  You can see your Queue-Fair settings in the Portal File Manager - they are updated when you hit Make Live.  For optimum performance, consider placing the cache folder on a small Ramdisk.

**3.** **IMPORTANT:** Make sure the system clock on your webserver is accurately set to network time! On unix systems, this is usually done with the ntp package.  It doesn't matter which timezone you are using.  For Debian/Ubuntu:

```
    sudo apt-get install ntp
```

**4.** Modify `anypage_controller.rb` and add the code from the `example_controller.rb` file in this distribution

**5.** Enter your account name and secret where indicated, and (optionally) the folder location you created in step 2.  You can also modify queue_fair_config.rb and preset these values there, which is more efficient than setting them with every page request.

**6.** Note the `QueueFairConfig.settings_file_cache_lifetime_minutes` setting - this is how often your web server will check for updated settings from the Queue-Fair queue servers (which change when you hit Make Live).   The default value is 5 minutes.  You can set this to 0 to download a fresh copy with every request but **DON'T DO THIS** on your production machine/live queue with real people, or your server may collapse under load.

**7.** Note the `QueueFairConfig.adapter_mode` setting.  "safe" is recommended - we also support "simple" - see the Technical Guide for further details.

**8.** **IMPORTANT** Note the `QueueFairConfig.debug` setting - this is set to true in the example code but you MUST set debug to false on production machines/live queues as otherwise your web logs will rapidly become full.  You can safely set it to a single IP address to just output debug information for a single visitor, even on a production machine.

That's it your done!

In your Ruby controllers you should always ensure that `adapter.go()` is the *first* thing that happens.  This will ensure that the Adapter is the first thing that runs when a vistor accesses any page, which is necessary both to protect your server from load from lots of visitors and also so that the adapter can set the necessary cookies.  You can add the adapter to all your controllers and use the Activation Rules in the Portal to set which pages on your site may trigger a queue.

In the case where the Adapter sends the request elsewhere (for example to show the user a queue page), `go()` will return False and the rest of the page should not be run.

If your web server is sitting behind a proxy, CDN or load balancer, you may need to edit the property sets in the example code to use values from forwarded headers instead.  If you need help with this, contact Queue-Fair support.

### To test the Server-Side Adapter

Use a queue that is not in use on other pages, or create a new queue for testing.

#### Testing SafeGuard
Set up an Activtion Rule to match the page you wish to test.  Hit Make Live.  Go to the Settings page for the queue.  Put it in SafeGuard mode.  Hit Make Live again.

In a new Private Browsing window, visit the page on your site.  

 - Verify that you can see debug output from the Adapter in your error-log.
 - Verify that a cookie has been created named `Queue-Fair-Pass-queuename`, where queuename is the System Name of your queue
 - If the Adapter is in Safe mode, also verify that a cookie has been created named QueueFair-Store-accountname, where accountname is the System Name of your account (on the Your Account page on the portal).
 - If the Adapter is in Simple mode, the Queue-Fair-Store cookie is not created.
 - Hit Refresh.  Verify that the cookie(s) have not changed their values.

#### Testing Queue
Go back to the Portal and put the queue in Demo mode on the Queue Settings page.  Hit Make Live.  Delete any Queue-Fair-Pass cookies from your browser.  In a new tab, visit https://accountname.queue-fair.net , and delete any Queue-Fair-Pass or Queue-Fair-Data cookies that appear there.  Refresh the page that you have visited on your site.

 - Verify that you are now sent to queue.
 - When you come back to the page from the queue, verify that a new QueueFair-Pass-queuename cookie has been created.
 - If the Adapter is in Safe mode, also verify that the QueueFair-Store cookie has not changed its value.
 - Hit Refresh.  Verify that you are not queued again.  Verify that the cookies have not changed their values.

**IMPORTANT:**  Once you are sure the Server-Side Adapter is working as expected, remove the Client-Side JavaScript Adapter tag from your pages, and don't forget to disable debug level logging by setting `QueueFairConfig.DEBUG` to `false` (its default value), and also set `QueueFairConfig.SETTINGS_FILE_CACHE_LIFETIMER_MINUTES` to at least 5 (also its default value).

**IMPORTANT:**  Responses that contain a Location header or a Set-Cookie header from the Adapter must not be cached!  You can check which cache-control headers are present using your browser's Inspector Network Tab.  The Adapter will add a Cache-Control header to disable caching if it sets a cookie or sends a redirect - but you must not override these with your own code or Rails framework.

### For maximum security

The Server-Side Adapter contains multiple checks to prevent visitors bypassing the queue, either by tampering with set cookie values or query strings, or by sharing this information with each other.  When a tamper is detected, the visitor is treated as a new visitor, and will be sent to the back of the queue if people are queuing.

 - The Server-Side Adapter checks that Passed Cookies and Passed Strings presented by web browsers have been signed by our Queue-Server.  It uses the Secret visible on each queue's Settings page to do this.
 - If you change the queue Secret, this will invalidate everyone's cookies and also cause anyone in the queue to lose their place, so modify with care!
 - The Server-Side Adapter also checks that Passed Strings coming from our Queue Server to your web server were produced within the last 30 seconds, which is why your clock must be accurately set.
 -  The Server-Side Adapter also checks that passed cookies were produced within the time limit set by Passed Lifetime on the queue Settings page, to prevent visitors trying to cheat by tampering with cookie expiration times or sharing cookie values.  So, the Passed Lifetime should be set to long enough for your visitors to complete their transaction, plus an allowance for those visitors that are slow, but no longer.
 - The signature also includes the visitor's USER_AGENT, to further prevent visitors from sharing cookie values.

## AND FINALLY

All client-modifiable settings are in the `QueueFairConfig` class.  You should never find you need to modify `queue_fair_adapter.rb` - but if something comes up, please contact support@queue-fair.com right away so we can discuss your requirements.

Remember we are here to help you! The integration process shouldn't take you more than an hour - so if you are scratching your head, ask us.  Many answers are contained in the Technical Guide too.  We're always happy to help!
