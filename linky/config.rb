# -*- coding: UTF-8 -*-
#
require 'linky/config/converter'

module Linky
  class Config
    class SettingNotFound < RuntimeError; end
    
    @@config_tables = []
    def self.add_config_table(sql)
      @@config_tables << sql
    end
    
    @@config_proxies = []
    def self.add_config_proxy(tablename, primkeys, value)
      $stderr.puts "Registered Config Proxy: #{tablename}"
      @@config_proxies << [ tablename, primkeys, value ]
    end
    
    @@configs = {}
    def self.add_config_set(klass, name, options)
      $stderr.puts "Registered SET: #{name}"
      @@configs[name] = options.update(:klass => klass)
    end
    def self.config(name)
      @@configs[name.downcase.to_sym]
    end
    
    add_config_table(<<-END_SQL)
      CREATE TABLE IF NOT EXISTS channel (
        channel VARCHAR(255) NOT NULL,
        name    VARCHAR(255) NOT NULL,
        value   TEXT         NOT NULL,
        PRIMARY KEY (channel, name)
      );
    END_SQL
    add_config_proxy(:channel, [ :channel, :name ], :value)
    
    class Proxy
      def initialize(db, tablename, primkeys, value)
        @db = db
        @tablename = tablename
        @primkeys = Array(primkeys)
        @value = value
        
        @where = @primkeys.collect { |k| "#{k} = ?" }.join(' AND ')
        @insert = ([ '?' ] * (@primkeys.size + 1)).join(', ')
      end
      
      def [](*args)
        if args.size != @primkeys.size
          raise ArgumentError, "wrong number of arguments (#{args.size} for #{@primkeys.size})"
        end
        @db.get_first_value("SELECT #{@value} FROM #{@tablename} WHERE #{@where}", *args)
      end
      
      def []=(*args)
        if args.size != @primkeys.size + 1
          raise ArgumentError, "wrong number of arguments (#{args.size} for #{@primkeys.size + 1})"
        end
        @db.execute("INSERT OR REPLACE INTO #{@tablename} VALUES ( #{@insert} )", *args)
      end
      
      def delete(*args)
        if args.size != @primkeys.size
          raise ArgumentError, "wrong number of arguments (#{args.size} for #{@primkeys.size})"
        end
        @db.execute("DELETE FROM #{@tablename} WHERE #{@where}", *args)
      end
    end
    
    def initialize(database)
      @db = SQLite3::Database.open(database)
      
      @@config_tables.each do |sql|
        sql.split(/;\n/).each do |stmt|
          @db.execute "#{stmt};"
        end
      end
      @@config_proxies.each do |tablename, primkeys, value|
        instance_variable_set "@#{tablename}", Proxy.new(@db, tablename, primkeys, value)
        (class << self; self; end).class_eval { attr_reader tablename.to_sym }
      end
    end
    
    def channels(name, value)
      @db.query("SELECT channel FROM channel WHERE name = ? AND value = ?", name, value).collect { |ch,| ch }
    end
    
    def persist_channels
      channels('persist', 1)
    end
  end
end
