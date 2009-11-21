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
      
      PRIO_REALLY_FIRST = 1
      PRIO_FIRST = 2
      PRIO_NORMAL = 3
      PRIO_LAST = 4
      PRIO_REALLY_LAST = 5
      class_inheritable_accessor :priority
      class_inheritable_array :prepend, :postpend
      self.priority = PRIO_NORMAL
      self.prepend = []
      self.postpend = []
      
      @@extensions = []
      def self.inherited(klass)
        super
        @@extensions << klass
      end
      
      def self.create_extensions(bot)
        extprio = {}
        @@extensions.each do |klass|
          klassname = klass.name.demodulize
          ary = (extprio[klass.priority] ||= [])
          i = 0
          while i < ary.length
            elt = ary[i]
            eltname = elt.name.demodulize
            unless elt.prepend.include?(klassname) || klass.postpend.include?(eltname)
              break if elt.postpend.include?(klassname) || klass.prepend.include?(eltname)
            end
            i += 1
          end
          ary.insert(i, klass)
        end
        
        extensions = extprio.sort.collect { |prio, klasses| klasses }.flatten.reverse
        extensions.inject(ActiveSupport::OrderedHash.new) { |hash, klass|
          $stderr.puts "Registered Extension: #{klass.name.demodulize}"
          hash[klass] = klass.new(bot); hash
        }
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
