# -*- coding: UTF-8 -*-
#
require 'linky/settings'
require 'set'
require 'thread'

module Linky
  module Extensions
    class Charset < Base
      self.priority = PRIO_REALLY_FIRST
      self.postpend = %w(IRCBase)
      
      config :charset,
             :args => [ :opt, String ],
             :usage => [ 'SET CHARSET <charset>', 'UNSET CHARSET' ]
      
      def initialize(bot)
        super
        @charsets = {}
      end
      
      def add_handlers
        irc.prepend_handler :incoming_msg,       wrap_method(:on_msg)
        irc.prepend_handler :incoming_msg,       wrap_method(:in_text)
        irc.prepend_handler :incoming_act,       wrap_method(:in_text)
        irc.prepend_handler :incoming_ctcp,      wrap_method(:in_text)
        irc.prepend_handler :incoming_notice,    wrap_method(:in_text)
        irc.prepend_handler :incoming_ctcpreply, wrap_method(:in_text)
        irc.prepend_handler :outgoing_privmsg,   wrap_method(:out_text)
        irc.prepend_handler :outgoing_notice,    wrap_method(:out_text)
      end
      
      private
      
      def set_charset(target, charset = nil)
        if !charset
          charset = charset(target)
        else
          charset.upcase!
          if Iconv.conv(charset, 'UTF-8', 'Unicode') == 'Unicode'
            config.channel[target, 'charset'] = charset.upcase
            @charsets[target] = charset
          else
            irc.msg target, "ERROR: \x02#{charset}\x02 is not compatible with ASCII."
            return
          end
        end
        irc.msg target, "SET CHARSET = #{charset}"
      end
      
      def unset_charset(target)
        config.channel.delete(target, 'charset')
        @charsets.delete(target)
        irc.msg target, "UNSET CHARSET"
      end
      
      def charset(target)
        @charsets[target] ||= config.channel[target, 'charset'] || 'UTF-8'
      end
      
      def on_msg(fullactor, actor, target, text)
        if /^\#/ =~ target && charset(target) == 'UTF-8' && /\x1B\$B/ =~ text
          irc.msg target, "\0303UTF8-ize\x03 <\x0312#{actor}\x03> #{NKF.nkf('-Jwx -m0 --ms-ucs-map', text)}"
        end
      end
      
      def in_text(fullactor, actor, target, text)
        convert(text, 'UTF-8', charset(target))
      end
      
      def out_text(target, text)
        convert(text, charset(target), 'UTF-8')
        text.force_encoding(Encoding::ASCII_8BIT) if defined? Encoding
      end
      
      def convert(text, to, from)
        text.replace(Utils.safe_iconv(to, from, text))
      end
    end
  end
end
