# -*- coding: UTF-8 -*-
#

module Linky
  module Extensions
    module Wrapper
      def wrap_method(name)
        method = method(name)
        lambda do |*args|
          # irc.report "#{self.class}\##{name}: #{args.inspect}"
          begin
            method.call(*args)
          rescue SystemExit
            raise
          rescue Exception => e
            irc.report "--- Exception #{e.class} during #{self.class}\##{name}"
            irc.report e.message
            e.backtrace.each { |t| irc.report "\tfrom #{t}" }
            
            if method.arity >= 3
              begin
                mesg = e.message.to_s.strip.gsub(/\n/, '/')
                if mesg.empty?
                  mesg = (e.class == RuntimeError) ? "unhandled exception" : e.class.to_s
                end
                mesg = "\x02[Bug]\x02 \x0312#{e.class}\x03: #{mesg}"
                
                irc.msg args[2], mesg
              rescue SystemExit
                raise
              rescue Exception => e
                irc.report "--- !!! Nested exception #{e.class}"
                irc.report e.message
                e.backtrace.each { |t| irc.report "\tfrom #{t}" }
              end
            end
          end
        end
      end
    end
    
    module ClassMethods
      def config_table(sql)
        Config.add_config_table(sql)
      end
      
      def config_proxy(tablename, primkeys, value)
        Config.add_config_proxy(tablename, primkeys, value)
      end
      
      def config(name, options)
        Config.add_config_set(self, name.to_sym, options)
      end
    end
    
    class Base
      include Wrapper
      extend ClassMethods
      attr_reader :bot, :irc, :options
      
      @@extensions = []
      
      def self.inherited(klass)
        @@extensions << klass
        super
      end
      
      def self.create_extensions(bot)
        @@extensions.inject(ActiveSupport::OrderedHash.new) { |hash, klass| hash[klass] = klass.new(bot); hash }
      end
      
      def initialize(bot)
        @bot = bot
        @irc = @bot.irc
        @options = @bot.options
      end
      
      def add_handlers
        # placeholder
      end
    end
  end
end
