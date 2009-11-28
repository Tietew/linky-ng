# -*- coding: UTF-8 -*-
#
require 'linky/config'
require 'linky/cache'
require 'linky/utils'
require 'linky/extensions'
require 'linky/irc_base'

module Linky
  class Bot < IRCBot
    include Extensions::Wrapper
    attr_reader :irc, :config, :cache, :options, :extensions, :commands
    
    def initialize(options)
      @options = options.dup
      @extensions = @extthreads = nil
      @mutex = Mutex.new
      
      extensions = Array(@options[:extensions] || '*').flatten
      Dir["linky/extensions/**/*.rb"].each do |f|
        klassname = f.camelize.sub(/^Linky::Extensions::/, '')
        if extensions.find { |matcher| !(/^\!/ =~ matcher) != !File.fnmatch(matcher.sub(/^\!/, ''), klassname) }
          require f
        end
      end
      
      @config = Config.new(@options[:database])
      @cache = Cache.new(@options[:cache])
      nickname = @options[:nickname]
      
      @options[:username] ||= BOTNAME
      @options[:realname] ||= BOTNAME
      @options[:nicknames] = [nickname] + (0..99).collect { |i| nickname + i.to_s }
      super @options
      
      setup_traps
      connect_socket
      start_listening
    end
    
    def bot_version
      "#{BOTNAME} #{BOTVERSION} (Net::YAIL #{Net::YAIL::VERSION}; #{RUBY_DESCRIPTION})"
    end
    
    def channel_locked?(channel)
      @config.channel[channel, 'persist'] == '1'
    end
    
    def connect_socket
      @mutex.synchronize do
        @extensions.each { |klass, x| x.shutdown } if @extensions
        @extensions = nil
        @extthreads.each(&:kill) if @extthreads
        @extthreads = nil
      end
      super
    end
    
    def register_thread(*args, &block)
      @mutex.synchronize do
        (@extthreads ||= []) << Thread.new(*args, &block)
      end
    end
    
    private
    
    def setup_traps
      trap(:INT)  { @irc.quit "SIGINT received.";  sleep 1; exit }
      trap(:TERM) { @irc.quit "SIGTERM received."; sleep 1; exit }
      trap(:HUP)  { @irc.quit "SIGHUP received.";  sleep 1; exit 193 }
      trap(:QUIT) { @irc.quit "SIGQUIT received."; sleep 1; exit 193 }
    end
    
    def add_custom_handlers
      @extensions = Extensions::Base.create_extensions(self)
      @commands = (@extensions.values + [self]).inject({}) do |hash, x|
        x.methods.each do |method|
          if /^command_/ =~ method
            hash[command = $'] = x  #'
            $stderr.puts "Registered Command: #{command} for #{x.class.name.demodulize}"
          end
        end
        hash
      end
      
      @irc.prepend_handler :incoming_welcome, wrap_method(:on_welcome)
      @irc.prepend_handler :incoming_invite,  wrap_method(:on_invite)
      @irc.prepend_handler :incoming_kick,    wrap_method(:on_kick)
      @irc.prepend_handler :incoming_mode,    wrap_method(:on_mode)
      @extensions.values.each(&:add_handlers)
    end
    
    def on_welcome(text, args)
      @channels = (@options[:channels] || []) | @config.persist_channels
    end
    
    def on_invite(fullactor, actor, target)
      join target
      msg target, "Hello, #{actor}. I am #{BOTNAME} IRCBot."
    end
    
    def on_kick(fullactor, actor, channel, user, text)
      if user == @irc.me && channel_locked?(channel)
        Thread.new do
          sleep 1
          join channel
          @irc.notice channel, "Oops!"
        end
      end
    end
    
    def on_mode(fullactor, actor, target, modes, objects)
      modes = modes.split(//)
      if modes.shift == '+'
        modes.zip(objects.split).each do |mode, nick|
          if mode == 'o' && nick == @irc.me
            @irc.mode target, '-o', @irc.me
            @irc.act target, "does not want channel operator."
            return
          end
        end
      end
    end
    
    public
    
    def command_version(actor, target, args)
      msg target, bot_version
    end
    
    def command_bye(actor, target, args)
      @irc.notice target, "Bye!"
      Thread.new { sleep 1; @irc.quit "Bye-bye"; sleep 1; exit }
    end
  end
end
