# -*- coding: UTF-8 -*-
#

module Linky
  module Extensions
    class CodeConv < Base
      include Utils
      
      def command_echo(actor, target, args)
        @irc.msg target, unescapeHTML(unescape(args))
      end
      
      def command_convert(actor, target, args)
        charset, text = args.split(/\s+/, 2)
        unless charset
          @irc.msg target, "usage: CONVERT <charset> <string...>"
          return
        end
        begin
          Iconv.new('UTF-8', charset)
        rescue
          @irc.msg target, "ERROR: can't handle \x02#{charset}\x02"
          return
        end
        
        text = unescapeHTML(unescape(text))
        text = safe_iconv(charset, 'UTF-8', text) do |e|
          if e = utf8toucs(e)
            (r = Utils::HTMLENTITIES_INV[e]) ? "&#{r};" : "&\##{e};"
          else
            "\x0314?\x03"
          end
        end
        @irc.msg target, safe_iconv('UTF-8', charset, text)
      end
      
      def command_capitalize(actor, target, args)
        do_chars('capitalize', target, args)
      end
      
      def command_upcase(actor, target, args)
        do_chars('upcase', target, args)
      end
      
      def command_downcase(actor, target, args)
        do_chars('downcase', target, args)
      end
      
      def do_chars(method, target, args)
        @irc.msg target, unescapeHTML(unescape(args)).mb_chars.send(method).to_s
      end
    end
  end
end
