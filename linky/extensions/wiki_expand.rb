# -*- coding: UTF-8 -*-
#
require 'linky/settings'
require 'uri'
require 'open-uri'

module Linky
  module Extensions
    class WikiExpand < Base
      self.postpend = %w(Command)
      
      config_table <<-END_SQL
        CREATE TABLE IF NOT EXISTS interwiki (
          prefix    VARCHAR(64)  NOT NULL PRIMARY KEY,
          url       TEXT         NOT NULL
        );
        CREATE TABLE IF NOT EXISTS interwiki_options (
          prefix    VARCHAR(64)  NOT NULL,
          optname   VARCHAR(64)  NOT NULL,
          optvalue  TEXT         NOT NULL,
          PRIMARY KEY (prefix, optname)
        );
        CREATE TABLE IF NOT EXISTS interlang (
          lang      VARCHAR(64)  NOT NULL PRIMARY KEY,
          url       VARCHAR(64)  NOT NULL
        );
        CREATE TABLE IF NOT EXISTS shortcut (
          wiki      VARCHAR(64)  NOT NULL,
          prefix    VARCHAR(64)  NOT NULL,
          namespace VARCHAR(64)  NOT NULL,
          PRIMARY KEY (wiki, prefix)
        );
      END_SQL
      config_proxy :interwiki, :prefix, :url
      config_proxy :interwiki_options, [ :prefix, :optname ], :optvalue
      config_proxy :interlang, :lang, :url
      config_proxy :shortcut, [ :wiki, :prefix ], :namespace
      
      config :interwiki,
             :args => [ /^[\w\-]+$/, :opt, Array ],
             :invalid => "interwiki name can't contain symbols.",
             :usage => [ 'SET INTERWIKI <wiki> [url] [optname=optvalue ...]',
                         'UNSET INTERWIKI <wiki>' ]
      config :interlang,
             :args => [ /^[\w\-]+$/, :opt, /^[\w\-]+$/ ],
             :invalid => "interlang name can't contain symbols.",
             :usage => [ 'SET INTERLANG <lang> [url]',
                         'UNSET INTERLANG <lang>' ]
      config :shortcut,
             :args => [ /^([\w\-]+(:[\w\-]+)?|\*)$/, /^[\w\-]+$/, :opt, String ],
             :invalid => "interwiki name and/or prefix can't contain symbols.",
             :usage => [ 'SET SHORTCUT <wiki / wiki:lang / lang / *> <prefix> [namespace]',
                         'UNSET SHORTCUT <wiki / wiki:lang / lang / *> <prefix>' ]
      
      IW_OPTIONS = %w(capitalize charset space)
      
      def add_handlers
        irc.prepend_handler :incoming_msg, wrap_method(:on_msg)
      end
      
      def command_sizeof(actor, target, args)
        if args.sub!(/\s+(\d+)$/, '')
          oldid = $1.to_i
        end
        title = args.strip
        
        wiki, lang = get_defaults(target)
        url, title, wiki, lang = expand(title, wiki, lang)
        
        redirect = 0
        urlhash = {}
        check_redir = proc do |uri|
          throw :error, "(#{uri.host}) \x0303#{title}\x03: Too many redirects" if (redirect += 1) >= 10
          throw :error, "(#{uri.host}) \x0303#{title}\x03: Redirection loop" if urlhash[uri.to_s]
          urlhash[uri.to_s] = 1
        end
        
        Thread.new do
          bugtrap(target, "sizeof") do
            uri = URI.parse(url)
            uri.query ||= ''
            uri.query.sub!(/(^|&)action=[^&]*/, '')
            uri.query.sub!(/(^|&)redirect=[^&]*/, '')
            uri.query = "#{uri.query}&action=raw&redirect=no".sub(/^&/, '')
            uri.query << "&oldid=#{oldid}" if oldid
            resp = Timeout.timeout(10) {
              $stderr.puts "[sizeof] query #{uri}"
              Net::HTTP.start(uri.host, uri.port) { |http| http.request_get(uri.request_uri) }
            }
            case resp.code
            when '301', '302', '303', '307'
              check_redir.call(uri)
              url = resp['Location']
              retry
            when '200'
              if /^#REDIRECT.*\[\[(.*?)(\|.*?)?\]\]/i =~ resp.body
                check_redir.call(uri)
                url, title, wiki, lang = expand($1, wiki, lang)
                retry
              end
              irc.msg target, "(#{uri.host}) \x0303#{title}\x03: #{Utils.num3(resp.body.size)} bytes"
            else
              irc.msg target, "(#{uri.host}) \x0303#{title}\x03: #{resp.code} \x02#{resp.message}\x02"
            end
          end
        end
      end
      
      private
      
      def set_interwiki(target, wiki, *args)
        wiki.downcase!
        
        unless args.empty?
          unless /^\w+=/ =~ args.first
            url = args.shift
          end
          
          options = []
          args.each do |opt|
            optname, optvalue = opt.split('=', 2)
            unless optname && optvalue
              irc.msg target, "ERROR: Invalid arguments for SET INTERWIKI"
              return
            end
            
            optname.downcase!
            unless IW_OPTIONS.include?(optname)
              irc.msg target, "ERROR: Unknown interwiki options #{optname}"
              return
            end
            unless optvalue.empty?
              case optname
              when 'charset'
                unless ((Iconv.conv(optvalue, 'UTF-8', 'Unicode') rescue false))
                  irc.msg target, "ERROR: Unknown charset #{optvalue}"
                  return
                end
              when 'capitalize'
                optvalue.downcase!
                unless optvalue == 'ascii' || optvalue == 'unicode'
                  irc.msg target, "ERROR: Unknown capitalize option; valids are `ASCII' or `Unicode'."
                  return
                end
              end
            end
            options << [ optname, optvalue ]
          end
          
          if url
            config.interwiki[wiki] = url
          else
            url = config.interwiki[wiki]
          end
          unless options.empty?
            unless url
              irc.msg target, "ERROR: Interwiki #{wiki} is not defined."
              return
            end
            options.each do |optname, optvalue|
              if optvalue.empty?
                config.interwiki_options.delete(wiki, optname)
              else
                config.interwiki_options[wiki, optname] = optvalue
              end
            end
          end
        end
        if url ||= config.interwiki[wiki]
          mesg = url.inspect
          IW_OPTIONS.each do |optname|
            if optvalue = config.interwiki_options[wiki, optname]
              mesg << " #{optname}=#{optvalue.inspect}"
            end
          end
          irc.msg target, "SET INTERWIKI #{wiki} = #{mesg}"
        else
          irc.msg target, "UNSET INTERWIKI #{wiki}"
        end
      end
      
      def unset_interwiki(target, wiki)
        wiki.downcase!
        config.interwiki.delete(wiki)
        IW_OPTIONS.each do |optname|
          config.interwiki_options.delete(wiki, optname)
        end
        irc.msg target, "UNSET INTERWIKI #{wiki}"
      end
      
      def set_interlang(target, lang, url = nil)
        lang.downcase!
        if url
          config.interlang[lang] = url
        else
          url = config.interlang[lang]
        end
        irc.msg target, "SET INTERLANG #{lang} = #{url}"
      end
      
      def unset_interlang(target, lang)
        lang.downcase!
        config.interlang.delete(lang)
        irc.msg target, "UNSET INTERLANG #{lang}"
      end
      
      def set_shortcut(target, wiki, prefix, namespace = nil)
        wiki.downcase!
        if namespace
          config.shortcut[wiki, prefix] = namespace
        else
          namespace = config.shortcut[wiki, prefix]
        end
        irc.msg target, "SET SHORTCUT #{wiki} #{prefix} = #{namespace}"
      end
      
      def unset_shortcut(target, wiki, prefix)
        wiki.downcase!
        config.shortcut.delete(wiki, prefix)
        irc.msg target, "UNSET SHORTCUT #{wiki} #{prefix}"
      end
      
      def get_defaults(target)
        wiki = config.channel[target, 'default_wiki'] || 'w'
        lang = config.channel[target, 'default_lang'] || 'en'
        [ wiki, lang ]
      end
      
      def expand(title, wiki, lang)
        title = Utils.unescape(Utils.unescapeHTML(title)).strip
        title, fragment = title.split('#', 2)
        return unless title
        title.gsub!(/[\x00-\x1F\|\[\]\<\>\{\}\x7F]/u, '')
        return if title.empty?
        
        while /^([^:]+):/ =~ title
          ns, nname = $1, $' #'
          found = nil
          [ "#{wiki}:#{lang}", lang, wiki, '*' ].each { |key| break if found = config.shortcut[key, ns] }
          if found
            title = "#{found}:#{nname}"
            break
          end
          
          ns.downcase!
          if interlang = config.interlang[ns]
            lang = interlang
          elsif url = config.interwiki[ns]
            lang = "en" if wiki == ns
            wiki = ns
          else
            break
          end
          title = nname
        end
        title.sub!(/^:+/, '')
        title.strip!
        
        url ||= config.interwiki[wiki] || config.interwiki[wiki = 'w']
        
        # capitalize
        if capitalize = config.interwiki_options[wiki, 'capitalize']
          titles = title.split(':', 2)
          case capitalize
          when 'ascii'
            titles.collect! { |t| t.sub(/^./u) { $&.upcase } }
          when 'unicode'
            titles.collect! { |t| t.sub(/^./u) { $&.mb_chars.upcase.to_s } }
          end
          title = titles.join(':')
        end
        
        # charset
        if charset = config.interwiki_options[wiki, 'charset']
          title = Utils.safe_iconv(charset, 'UTF-8', title)
        end
        
        # space
        if space = config.interwiki_options[wiki, 'space']
          etitle = Utils.escape(title).gsub(/%20/, space)
        else
          title.gsub!(/\A_+|_+\z/, '')
          title.tr!(' ', '_')
          fragment.tr!(' ', '_') if fragment
          etitle = Utils.escape(title)
        end
        
        # make url
        url.gsub!(/\{lang\}/, lang)
        url.gsub!(/\{title\}/, etitle)
        url << '#' << Utils.escape(fragment, '.') if fragment
        
        [ url, title, wiki, lang ]
      end
      
      def on_msg(fullactor, actor, target, text)
        return unless /\[\[/ =~ text
        target = actor if target == irc.me
        return if config.channel[target, 'nowiki'] == '1'
        
        wiki, lang = get_defaults(target)
        text.scan(/\[\[(.*?)\]\]/) do |title,|
          url, = expand(title, wiki, lang)
          irc.msg target, url if url
        end
      end
    end
  end
end
