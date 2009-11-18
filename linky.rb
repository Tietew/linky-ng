#!/usr/bin/ruby -Ku
# -*- coding: UTF-8 -*-
#
require 'optparse'
require 'rubygems'
require 'net/yail/IRCBot'
require 'sqlite3'
require 'thread'
require 'yaml'

module Linky
  BOTNAME = 'linky-ng'
  BOTVERSION = '0.1.0'
  DATADIR = File.dirname(__FILE__) + '/data'
  DEFAULT_CONFFILE = 'linky.yml'
end

begin
  options = OptionParser.getopts("c:vs", "help")
  raise if options['help']
  config = YAML.load(File.read(options['c'] || 'linky.yml'))
  config[:loud] = true if options['v']
  config[:silent] = true if options['s']
rescue => e
  warn e.message unless e.message.empty?
  warn "usage: #$0 [-c CONFFILE] [-v] [-s] [--help]"
  exit 1
end

$stdout.sync = $stderr.sync = true
require 'linky/bot'
bot = Linky::Bot.new(config)
bot.irc_loop
