# -*- coding: UTF-8 -*-
#
require 'iconv'
require 'nkf'

module Linky
  module Utils
    module_function
    
    HTMLENTITIES = YAML.load(File.read(DATADIR + '/htmlentities.yml'))
    HTMLENTITIES_INV = HTMLENTITIES.invert
    HTMLESCAPE = { '<' => '&lt;', '>' => '&gt;', '&' => '&amp;', '"' => '&quot;' }
    
    def escape(str, prefix = '%')
      str.to_s.gsub(%r{([^a-zA-Z0-9\-=@:,./_]+)}n) {
        prefix + $1.unpack('H2' * $1.bytesize).join(prefix).upcase
      }
    end
    
    def unescape(str)
      str.gsub(/%(?:u([\dA-Fa-f]{4})|([\dA-Fa-f]{2}))/u) { $1 ? ucstoutf8($1.hex) : $2.hex.chr }
    end
    
    def escapeHTML(str)
      str.to_s.gsub(/[<>&"]/) { HTMLESCAPE[$&] } #"
    end
    
    def unescapeHTML(str)
      str.to_s.gsub(/&(?:#(?:x([\dA-Fa-f]+)|(\d+))|([A-Za-z\d]+));/u) {
        if $3
          ucstoutf8(HTMLENTITIES[$3]) || $&
        else
          ucstoutf8($1 ? $1.hex : $2.to_i) || $&
        end
      }
    end
    
    def utf8toucs(str)
      str.unpack('U')[0]
    rescue ArgumentError, RangeError
      nil
    end
    
    def ucstoutf8(chr)
      [ chr ].pack('U*')
    rescue ArgumentError, RangeError
      nil
    end
    
    def safe_iconv(to, from, str, ech = "?")
#      if /^ISO-?2022-?JP$/ =~ from
#        str = jis2sjis(str)
#        from = "Windows-31J"
#      end
#      if /^ISO-?2022-?JP$/ =~ to
#        to = "Windows-31J"
#        tojis = true
#      end
      iconv = Iconv.new(to, from)
      result = ""
      offset = 0
      block = block_given?
      
      utf8 = (/^UTF-?8$/i =~ from)
      begin
        result << iconv.iconv(str, offset)
      rescue Iconv::IllegalSequence => e
        return unless ech || block
        str = e.failed
        if utf8
          if utf8toucs(str)
            offset = /^./u.match(str)[0].size
          else
            offset = 1
            until utf8toucs(str[offset, 6])
              offset += 1
            end
          end
        else
          offset = 1
        end
        ech = yield(str[0, offset]) if block
        result << e.success << iconv.iconv(ech)
        retry
      rescue Iconv::Failure => e
        return unless ech
        result << e.success
      end
      result << iconv.close
#      if tojis
#        sjis2jis(result)
#      else
        result
#      end
    end
    
    def clean_utf8(str, ech = '')
      safe_iconv('UTF-8', 'UTF-8', str, ech)
    end
    
    def sjis2jis(str)
      result = ""
      str.split(/([\x00-\x0F])/s).each_slice(2) { |s1, s2|
        result << NKF.nkf('-SjX --ms-ucs-map', s1)
        result << s2 if s2
      }
      result
    end
    
    def jis2sjis(str)
      result = ""
      str.split(/([\x00-\x0F])/n).each_slice(2) { |s1, s2|
        result << NKF.nkf('-JsX --ms-ucs-map', s1)
        result << s2 if s2
      }
      result
    end
    
    def num3(number)
      f = number.to_f
      i = number.to_i
      us = sprintf("%.2f", f)[/\.\d+$/] if f != i
      i.to_s.reverse.scan(/.{1,3}/).join(',').reverse + us.to_s
    end
  end
end
