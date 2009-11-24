# -*- coding: UTF-8 -*-
#
require 'linky/settings'

module Linky
  module Extensions
    class StatusReport < Base
      def add_handlers
        bot.register_thread(&method(:report_thread))
      end
      
      def command_status(actor, target, args)
        report = mkreport
        Thread.new { sleep 1; sendreport(target, report) }
      end
      
      private
      
      def report_thread
        sleep 60
        loop do
          channels = config.channels('statusreport', 1)
          Thread.new(channels, mkreport, &method(:do_report)) if channels.present?
          sleep 3600
        end
      end
      
      def mkreport
        status = File.read('/proc/self/status')
        vmrss = status[/^VmRSS:\s*(\d+)/, 1]
        vmhwm = status[/^VmHWM:\s*(\d+)/, 1]
        
        report = [
          "[linky-ng STATUS REPORT]",
          "Uptime: #{bot.get_uptime_string}",
          "Threads: #{Thread.list.size} RSS: #{vmrss}kB (max #{vmhwm}kB)",
        ]
        if defined? GC.enable_stats
          report << "GC: count=%d time=%.1fms alloc=%.1fKiB objects=%d" %
                      [ GC.collections, GC.time / 1000.0, GC.allocated_size / 1024.0, ObjectSpace.live_objects ]
        end
        report
      end
      
      def do_report(channels, report)
        channels.each do |target|
          sendreport(target, report)
        end
      end
      
      def sendreport(target, report)
        report.each do |mesg|
          irc.notice target, mesg
          sleep 1
        end
      end
    end
  end
end
