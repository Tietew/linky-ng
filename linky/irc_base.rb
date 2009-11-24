# -*- coding: UTF-8 -*-
#
require 'set'

module Linky
  module Extensions
    class IRCBase < Base
      self.priority = PRIO_REALLY_FIRST
      
      attr_reader :nicklist
      
      EMPTY_CHANNEL_WAIT_SECS = 60
      
      def initialize(bot)
        super
        @nicklist = Hash.new { |h, k| h[k] = Set.new }
        @nickmutex = Mutex.new
        @nickthread = {}
      end
      
      def add_handlers
        irc.prepend_handler :incoming_welcome,    wrap_method(:on_welcome)
        irc.prepend_handler :incoming_notice,     wrap_method(:on_notice)
        irc.prepend_handler :incoming_nick,       wrap_method(:on_nick)
        irc.prepend_handler :incoming_namreply,   wrap_method(:on_namreply)
        irc.prepend_handler :incoming_endofnames, wrap_method(:on_endofnames)
        irc.prepend_handler :incoming_join,       wrap_method(:on_join)
        irc.prepend_handler :incoming_part,       wrap_method(:on_part)
        irc.prepend_handler :incoming_quit,       wrap_method(:on_quit)
        irc.prepend_handler :incoming_kick,       wrap_method(:on_kick)
        irc.prepend_handler :incoming_ctcp,       wrap_method(:on_ctcp)
      end
      
      private
      
      # If my canonical nickname is already used, request NickServ to ghost it.
      # When ghosted, NickServ will send me NOTICE.
      # Otherwise, identify me.
      def on_welcome(text, args)
        @nickmutex.synchronize do
          @nicklist.clear
          @nickthread.each(&:kill)
          @nickthread.clear
        end
        if options[:nickpass] && irc.me != options[:nickname]
          irc.msg "NickServ", "ghost #{options[:nickname]} #{options[:nickpass]}"
        else
          irc.msg "NickServ", "identify #{options[:nickpass]}"
        end
      end
      
      # After NickServ notified my nickname has been ghosted,
      # change the nickname to my canonical one.
      def on_notice(fullactor, actor, target, text)
        if actor && actor.downcase == 'nickserv' && target == irc.me && /\bghosted\b/ =~ text
          irc.nick options[:nickname]
        end
      end
      
      # After my nickname has been changed to my canonical one, identify me.
      def on_nick(fullactor, actor, nickname)
        if irc.me == nickname
          irc.msg "NickServ", "identify #{options[:nickpass]}"
        end
        
        actor = actor.downcase
        nickname = nickname.downcase
        @nickmutex.synchronize do
          @nicklist.each do |target, nicklist|
            if nicklist.delete?(actor)
              nicklist.add(nickname)
            end
          end
        end
      end
      
      # Update member list.
      def on_namreply(text, args)
        flag, target, *members = text.split
        nicklist = members.collect { |name| name.sub(/^\W*/, '').downcase }
        @nickmutex.synchronize do
          @nicklist[target.downcase] |= nicklist
        end
      end
      
      # Member list has been fixed; check for empty channel.
      def on_endofnames(text, args)
        target, = text.split
        @nickmutex.synchronize do
          membercheck(target.downcase)
        end
      end
      
      # Update member list.
      def on_join(fullactor, actor, target)
        target = target.downcase
        @nickmutex.synchronize do
          @nicklist[target].add(actor.downcase)
          membercheck(target)
        end
      end
      
      # If I had parted, delete member list.
      # Otherwise, update member list and check for empty channel.
      def on_part(fullactor, actor, target, text)
        target = target.downcase
        @nickmutex.synchronize do
          if actor == irc.me
            @nicklist.delete(target)
            killwait(target)
          else
            @nicklist[target].delete(actor.downcase)
            membercheck(target)
          end
        end
      end
      
      # Update member lists of all channels and check for empty channels.
      def on_quit(fullactor, actor, text)
        unless actor == irc.me
          actor = actor.downcase
          @nickmutex.synchronize do
            @nicklist.each do |target, nicklist|
              nicklist.delete(actor)
              membercheck(target)
            end
          end
        end
      end
      
      # Same as on_part
      def on_kick(fullactor, actor, target, user, text)
        on_part(fullactor, user, target, text)
      end
      
      def membercheck(target)
        killwait(target)
        if @nicklist.key?(target)
          nicklist = @nicklist[target]
          irc.report "{#{target}} members = #{nicklist.sort.join(' ')}"
          return if nicklist.size >= 2 && nicklist.include?(irc.me)
          return if bot.channel_locked?(target)
        end
        @nickthread[target] = Thread.new(target, &method(:wait_empty))
      end
      
      def wait_empty(target)
        sleep EMPTY_CHANNEL_WAIT_SECS
        @nickmutex.synchronize do
          irc.part target, "Empty channel. Good-bye, #{target}."
        end
      end
      
      def killwait(target)
        if thread = @nickthread.delete(target)
          thread.kill
        end
      end
      
      # Respond to CTCP commands
      def on_ctcp(fullactor, actor, target, text)
        case text
        when 'VERSION'
          irc.ctcpreply(actor, "VERSION #{bot.bot_version}")
        when 'TIME'
          irc.ctcpreply(actor, "TIME #{Time.now.asctime}")
        when 'CLIENTINFO'
          irc.ctcpreply(actor, "CLIENTINFO Available CTCP commands: CLIENTINFO ERRMSG VERSION TIME PING")
        when /^PING /
          irc.ctcpreply(actor, "PING #{$'}")
        else
          irc.ctcpreply(actor, "ERRMSG #{text} :Unknown CTCP command")
        end
        true
      end
    end
  end
end
