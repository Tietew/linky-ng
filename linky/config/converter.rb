# -*- coding: UTF-8 -*-
#

module Linky
  class Config
    module Converter
      module ToSQL
        def self.boolean(value)
          case value.to_s
          when /\At(rue)?\z/i, /\Ay(es)?\z/, /\Aon\z/i, '1'
            1
          else
            0
          end
        end
        
        def self.integer(value)
          Integer(value) rescue 0
        end
        
        def self.text(value)
          value.to_s
        end
      end
      
      module FromSQL
        def self.boolean(value)
          value.to_s == '1' ? 'on' : 'off'
        end
        
        def self.integer(value)
          value.to_s
        end
        
        def self.text(value)
          value.to_s
        end
      end
    end
  end
end
