# -*- coding: UTF-8 -*-
#

module Linky
  class Cache
    CREATE_TABLE = <<-END_SQL
      CREATE TABLE IF NOT EXISTS cache (
        key     VARCHAR(255) NOT NULL PRIMARY KEY,
        value   TEXT         NOT NULL,
        expiry  INTEGER      NOT NULL
      );
      CREATE INDEX IF NOT EXISTS cache_expiry_index ON cache (expiry);
    END_SQL
    DEFAULT_EXPIRY = 60 * 60 * 24 * 7
    CLEANUP_PERIOD = 60 * 60
    
    def initialize(cache)
      @db = SQLite3::Database.open(cache)
      CREATE_TABLE.split(/;\n/).each { |stmt| @db.execute "#{stmt};" }
      cleanup :force
    end
    
    def fetch(namespace, key, max_age = DEFAULT_EXPIRY, &block)
      cleanup
      now = Time.now.to_i
      key = "#{namespace}:#{key}"
      unless value = @db.get_first_value("SELECT value FROM cache WHERE key = ? AND expiry > ?", key, now)
        if value = yield(key)
          @db.execute("INSERT OR REPLACE INTO cache VALUES ( ?, ?, ? )", key, value, now + max_age)
        end
      end
      value
    end
    
    private
    
    def cleanup(force = false)
      now = Time.now.to_i
      if force || now >= (@lastcleanup + CLEANUP_PERIOD)
        @db.execute("DELETE FROM cache WHERE expiry < ?", now)
        @lastcleanup = now
      end
    end
  end
end
