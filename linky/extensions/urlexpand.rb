# -*- coding: UTF-8 -*-
#
require 'net/http'

module Linky
  module Extensions
    class URLExpand < Base
      config_table <<-END_SQL
        CREATE TABLE IF NOT EXISTS urlexpand (
          host VARCHAR(64)  NOT NULL PRIMARY KEY,
          mode TEXT         NOT NULL
        );
      END_SQL
      config_proxy :urlexpand, :host, :mode
      
      config :urlexpand,
             :args => [ /^([A-Za-z\d\-]+\.)+[A-Za-z\d\-]+$/, :opt ],
             :usage => [ 'SET URLEXPAND <hostname>',
                         'UNSET URLEXPAND <hostname>' ]
      
      def initialize(bot)
        super
        @config = @bot.config
      end
      
      def add_handlers
        irc.prepend_handler :incoming_msg, wrap_method(:on_msg)
      end
      
      private
      
      def set_urlexpand(target, hostname)
        hostname.downcase!
        @config.urlexpand[hostname] = 'redirect'
        @irc.msg target, "SET URLEXPAND #{hostname} = redirect"
      end
      
      def unset_urlexpand(target, hostname)
        hostname.downcase!
        @config.urlexpand.delete(hostname)
        @irc.msg target, "SET URLEXPAND #{hostname}"
      end
      
      def on_msg(fullactor, actor, target, text)
        dupe = {}
        target = actor if target == @irc.me
        
        text.scan(%r{h?ttp?://(.*?)/(\S+)}) do |host, path|
          host.downcase!
          key = "#{host}/#{path}"
          unless dupe[key]
            if @config.urlexpand[host]
              Thread.new(target, host, path, &method(:expand))
            end
            dupe[key] = 1
          end
        end
      end
      
      def expand(target, host, path)
        key = "#{host}/#{path}"
        url = @config.cache(:urlexpand, key) do
          resp = Net::HTTP.start(host) { |http| http.request_get("/#{path}") }
          resp.code == '301' || resp.code == '302' ? resp['Location'] : 'Not Found'
        end
        @irc.msg target, "#{host} (#{path}): #{url}"
      end
    end
  end
end
