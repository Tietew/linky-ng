# -*- coding: UTF-8 -*-
#
require 'linky/command'
require 'shellwords'

module Linky
  module Extensions
    class Settings < Base
      def initialize(bot)
        super
        @setting = YAML.load(File.read(DATADIR + '/setting.yml'))
      end
      
      def command_set(actor, target, args)
        args = Shellwords.shellwords(args)
        unless name = args.shift
          irc.msg target, "usage: SET <name> [args...]"
          return
        end
        name.downcase!
        
        # channel setting
        if set = @setting[name]
          case args.size
          when 0
            value = config.channel[target, name]
          when 1
            value = Config::Converter::ToSQL.send(set['value'], args[0].strip)
            config.channel[target, name] = value
          else
            irc.msg target, "usage: #{set['usage']}"
            return
          end
          irc.msg target, "SET #{name.upcase} = #{Config::Converter::FromSQL.send(set['value'], value)}"
          return
        end
        
        # extension setting
        if set = Config.config(name)
          return unless args = checkargs(target, name, set, args, :set)
          bot.extensions[set[:klass]].send("set_#{name}", target, *args)
          return
        end
        
        irc.msg target, "ERROR: #{name.upcase}: Unknown setting name."
      end
      
      def command_unset(user, target, args)
        args = Shellwords.shellwords(args)
        unless name = args.shift
          irc.msg target, "usage: UNSET <name> [args...]"
          return
        end
        name.downcase!
        
        # channel setting
        if set = @setting[name]
          unless args.empty?
            irc.msg target, "usage: UNSET #{name.upcase}"
            return
          end
          config.channel.delete(target, name)
          irc.msg target, "UNSET #{name.upcase}"
          return
        end
        
        # extension setting
        if set = Config.config(name)
          return unless args = checkargs(target, name, set, args, :unset)
          bot.extensions[set[:klass]].send("unset_#{name}", target, *args)
          return
        end
        
        irc.msg target, "ERROR: #{name.upcase}: Unknown setting name."
      end
      
      def checkargs(target, name, set, args, mode)
        reqargs = set[:args].dup
        actargs = []
        optional = false
        reqargs.pop if mode == :unset
        
        while pattern = reqargs.shift
          if pattern == :opt
            optional = true
            next
          end
          
          unless arg = args.shift
            break if optional
            irc.msg target, "usage: #{set[:usage][mode == :set ? 0 : 1]}"
            return
          end
          
          valid = true
          case pattern
          when Regexp
            valid = (pattern =~ arg)
          when Integer
            arg = Integer(arg) rescue valid = false
          when Float
            arg = Float(arg) rescue valid = false
          when String
            # ok
          when Array
            actargs << arg
            actargs.concat(reqargs)
            break
          end
          unless valid
            mesg = set[:invalid] || "Invalid arguments for SET #{name.upcase}"
            irc.msg target, "ERROR: #{mesg}"
            return
          end
          actargs << arg
        end
        
        actargs
      end
    end
  end
end
