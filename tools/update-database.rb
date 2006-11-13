#!/usr/bin/env ruby

require 'bitclust'
require 'fileutils'
require 'net/smtp'
require 'socket'
require 'time'
require 'optparse'

include FileUtils

def main
  version = '1.9.0'
  host = nil
  port = Net::SMTP.default_port
  from = nil
  to = nil

  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')}"
  parser.on('--from=ADDR', 'SMTP host to send mail.') {|addr|
    from = addr
  }
  parser.on('--to=ADDR', 'SMTP host to send mail.') {|addr|
    to = addr
  }
  parser.on('--smtp-host=NAME', 'SMTP host to send mail.') {|name|
    host = name
  }
  parser.on('--smtp-port=NUM', 'SMTP port to send mail.') {|num|
    port = num.to_i
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  unless ARGV.size == 1
    $stderr.puts "wrong number of argument (expected 1)"
    exit 1
  end
  cwd = ARGV[0]
  reporter = SMTPReporter.new(:host => host, :port => port,
                              :from => from, :to   => to)
  begin
    update_database "#{cwd}/var/#{version}", "#{cwd}/src", version
    clear_error
  rescue BitClust::Error => err
    reporter.report_error err if new_error?(err)
    save_error err
  end
end

def update_database(dbdir, doctree, version)
  tmpdir = 'db.tmp'
  build_database tmpdir, doctree, version
  mv datadir, 'db.old'
  mv tmp, dbdir
ensure
  rm_rf 'db.old'
  rm_rf tmpdir
end

def build_database(prefix, doctree, version)
  db = BitClust::Database.new(prefix)
  db.init
  db.transaction {
    db.propset 'version', version
    db.propset 'encoding', 'euc-jp'
  }
  db.transaction {
    db.update_by_stdlibtree doctree
  }
end

LASTLOG_FILE = 'lasterror.log'

def new_error?(err)
  return true unless File.exist?(LASTLOG_FILE)
  serialize_error(err) != File.read(LASTLOG_FILE)
end

def save_error(err)
  File.open(LASTLOG_FILE, 'w') {|f|
    f.write serialize_error(err)
  }
end

def clear_error
  rm_f LASTLOG_FILE
end

def serialize_error(err)
  msgline = "#{err.message} (#{err.class})"
  backtraces = err.backtrace.map {|s| "\t#{s}" }
  ([msgline] + backtraces).join("\n")
end

def cmd(*args)
  st = cmd_f(*args)
  unless st.exitstatus == 0
    raise CommandFailed, "command failed: #{args.map {|a| a.inspect }.join(' ')"
  end
end

def cmd_f(*args)
  pid = Process.fork {
    Process.exec(*args)
  }
  _, st = *Process.waitpid2(pid)
  st
end

class SMTPReporter
  def initialize(h)
    @host = h[:host]
    @port = h[:port]
    @from = h[:from]
    @to = h[:to]
  end

  def report_error(err)
    send_message "[build error] #{err.message}", serialize_error(err)
  end

  private

  def send_message(subject, body)
    Net::SMTP.start(@host, @port, Socket.gethostname) {|smtp|
      smtp.send_mail(<<-End, from, to)
Date: #{Time.now.rfc2822}
From: #{@from}
To: #{@to}
Subject: #{subject}

#{body}
      End
    }
  end
end

main
