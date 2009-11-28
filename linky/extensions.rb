# -*- coding: UTF-8 -*-
#

module Linky
  module Extensions
    module Wrapper
      def wrap_method(name)
        method = method(name)
        lambda do |*args|
          bugtrap(method.arity >= 3 ? args[2] : nil, "#{self.class}\##{name}") do
            method.call(*args)
          end
        end
      end
      
      def bugcheck(e, target = nil, context = nil)
        $stderr.puts "--- Exception #{e.class}#{" during #{context}" if context}"
        $stderr.puts e.message
        e.backtrace.each { |t| $stderr.puts "\tfrom #{t}" }
        
        if target
          mesg = e.message.to_s.strip.gsub(/\n/, '/')
          mesg = (e.class == RuntimeError) ? "unhandled exception" : e.class.to_s if mesg.empty?
          mesg = "\x02[Bug]\x02 \x0312#{e.class}\x03: #{mesg}"
          irc.msg target, mesg
        end
      rescue SystemExit
        raise
      rescue Exception => e
        $stderr.puts "--- !!! Nested exception #{e.class}"
        $stderr.puts e.message
        e.backtrace.each { |t| $stderr.puts "\tfrom #{t}" }
      end
      
      def bugtrap(target = nil, context = nil)
        mesg = catch(:error) { return yield }
        irc.notice target, "ERROR: #{mesg}" if target && mesg
      rescue SystemExit
        raise
      rescue Exception => e
        bugcheck(e, target, context)
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
      attr_reader :bot
      delegate :irc, :options, :config, :cache, :to => :@bot
      
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
      end
      
      def add_handlers
        # placeholder
      end
      
      def shutdown
        # placeholder
      end
    end
  end
end
