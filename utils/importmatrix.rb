#!/usr/bin/ruby -Ku
# -*- coding: UTF-8 -*-
#
require 'rubygems'
require 'open-uri'
require 'rexml/document'
require 'sqlite3'

db = SQLite3::Database.new(ARGV[0] || 'db/config.sqlite')
db.transaction do
  f = open('http://en.wikipedia.org/w/api.php?action=query&meta=siteinfo&siprop=interwikimap&format=xml', 'r')
  doc = REXML::Document.new(f.read)
  REXML::XPath.match(doc, '/api/query/interwikimap/iw').each do |iw|
    prefix = iw.attributes['prefix']
      url = iw.attributes['url'].gsub(/\$1/, '{title}')
    
    if iw.attributes['language']
      lang = url[%r{//(.*?)\.}, 1] || prefix
      db.execute "INSERT OR REPLACE INTO interlang VALUES ( ?, ? )", prefix, lang
    else
      if iw.attributes['local']
        url.sub!(%r{//en\.}, '//{lang}.')
      end
      db.execute "INSERT OR REPLACE INTO interwiki VALUES ( ?, ? )", prefix, url
    end
  end
end
db.close
