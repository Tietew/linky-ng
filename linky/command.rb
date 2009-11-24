# -*- coding: UTF-8 -*-
#
module Linky
  module Extensions
    class Command < Base
      def add_handlers
        irc.prepend_handler :incoming_msg,     wrap_method(:on_msg)
      end
      
      def on_msg(fullactor, actor, target, text)
        return if actor == irc.me
        
        target = actor if target == irc.me
        if /\A(?:#{irc.me}[:,]\s*|\\)([A-Za-z]\w*)/ =~ text
          command, args = $1, $' #'
          if cobj = bot.commands[command]
            cobj.__send__("command_#{command}", actor, target, args.strip)
            return
          end
          irc.notice target, "#{command}: command not found."
          return
        end
      end
    end
  end
end
