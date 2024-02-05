# frozen_string_literal: true

require_relative 'app_logger'

LOG = AppLogger.setup(__FILE__) unless defined?(LOG)

module TimeoutInterface
  def timeout!(callback_proc, duration)
    SelectController.instance.add_timeout(callback_proc, duration)
  end

  def timeout?(callback_proc)
    SelectController.instance.timeout?(callback_proc)
  end

  def timeout_pop(callback_proc)
    SelectController.instance.remove_timeout(callback_proc)
  end
end

module SocketInterface
  def add_sock(readable_proc, sock)
    SelectController.instance.add_socket(readable_proc, sock)
  end

  def remove_sock(sock, close: true)
    SelectController.instance.remove_socket(sock, close: close)
  end

  def add_writeable(writeable_proc, sock)
    SelectController.instance.add_socket(writeable_proc, sock, for_write: true)
  end

  def remove_writeable(sock, close: true)
    SelectController.instance.remove_socket(sock, close: close, for_write: true)
  end
end

module SelectHandlerMethods
  def handle_err(err_socks)
    p([:error, err_socks])
    handle_readable(err_socks)
  end

  def handle_writeable(writeable)
    writeable.each do |sock|
      prc = @writeable[sock]
      next unless prc

      prc.arity.zero? ? prc.call : prc.call(sock)
    end
  end

  def handle_readable(readable)
    readable.each do |sock|
      prc = @sockets[sock]
      next unless prc

      prc.arity.zero? ? prc.call : prc.call(sock)
    end
  end

  def handle_timeouts
    current_time = Time.now
    touts = @timeouts.keys
    touts.each do |callback_proc|
      # p callback_proc
      timeout = @timeouts[callback_proc]
      next unless current_time >= timeout

      @timeouts.delete(callback_proc)
      callback_proc.call
    end
  end
end

class SelectController
  @instance = nil
  class << self
    def instance
      @instance ||= new
    end
  end
  private_class_method :new

  include SelectHandlerMethods

  attr_accessor :stdin_proc

  def initialize
    reset
  end

  def add_socket(call_proc, sock, for_write: false)
    raise "IO type required for socket argument: #{sock.class}" unless sock.is_a?(IO)
    raise "invalid proc detected: #{call_proc.class}" unless call_proc.respond_to?(:call)

    for_write ? @writeable[sock] = call_proc : @sockets[sock] = call_proc
  end

  def remove_socket(sock, close: true, for_write: false)
    # p [:removing, sock, sock.object_id]
    return if sock.nil? || sock.closed?

    sock.close if close
  ensure
    for_write ? @writeable.delete(sock) : @sockets.delete(sock)
  end

  def remove_socks(socks)
    socks.each { |sock| remove_socket(sock, close: true) }
    @writeable.each_key { |sock| remove_socket(sock, close: true, for_write: true) }
  end

  def stop
    remove_socks(@sockets.keys)
  end

  def timeout?(callback_proc)
    @timeouts[callback_proc]
  end

  def add_timeout(callback_proc, seconds)
    # p callback_proc
    raise 'positive value required for seconds parameter' unless seconds.positive?
    raise "invalid proc detected: #{callback_proc.class}" unless callback_proc.respond_to?(:call)

    @timeouts[callback_proc] = Time.now + seconds
  end

  def remove_timeout(callback_proc)
    @timeouts.delete(callback_proc)
  end

  def reset
    @stdin_proc = nil
    @sockets = { $stdin => proc {} }
    @writeable = {}
    @timeouts = {}
    at_exit do
      stop
    end
  end

  def run
    result = select_socks until result == $stdin
    req = $stdin.gets.chomp
    # $stdout.puts([Time.now, 'ok', Process.pid])
    exit if req.include?("\x1B") || req.include?('exit')
    @stdin_proc&.call(req)
    run
  rescue StandardError => e
    LOG.error([:uncaught_exception_while_select, e.class, e.message])
    LOG.error("Backtrace:\n\t#{e.backtrace.join("\n\t")}")
    exit
  end

  private

  def socks
    @sockets.delete_if { |socket, _| socket.closed? }
    @sockets.keys
  end

  def run_select
    select(socks, @writeable.keys, socks, calculate_next_timeout)
  rescue IOError => e
    p([:io_error_in_select, e])
  end

  def select_socks
    # p @sockets
    readable, writeable, err = run_select
    # p readable
    return handle_err(err) if err && !err.empty?
    return $stdin if readable&.include?($stdin)

    handle_writeable(writeable) if writeable
    handle_readable(readable) if readable
    handle_timeouts
  end

  def calculate_next_timeout
    tnow = Time.now
    return nil if @timeouts.empty?

    [@timeouts.values.min, tnow].max - tnow
  end
end

# SelectController.instance.setup
