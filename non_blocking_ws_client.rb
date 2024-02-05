# frozen_string_literal: true

require 'socket'
require 'uri'
require_relative 'select_controller'

class WebSocketMessageAssembler
  def initialize
    @buffer = ''.dup
    @final_frame_received = false
  end

  # Adds a frame to the assembler and checks if it's the final frame
  def add_frame(fin, payload)
    @buffer << payload
    @final_frame_received = true if fin
  end

  # Checks if a complete message has been assembled
  def complete_message?
    @final_frame_received
  end

  # Retrieves the complete message and resets the assembler
  def message?
    return nil unless complete_message?

    message = @buffer.dup
    reset
    message
  end

  private

  # Resets the assembler for the next message
  def reset
    @buffer.clear
    @final_frame_received = false
  end
end

module WebSocketIncomingMethods
  def parse_frame_header(buffer)
    return nil if buffer.length < 2

    b1, b2 = buffer.unpack('C*')
    fin = (b1 & 0b10000000) == 0b10000000
    opcode = (b1 & 0b00001111)
    len_code = (b2 & 0b01111111)

    [fin, opcode, len_code]
  end

  def determine_payload_length(buffer, len_code)
    case len_code
    when 126
      return nil if buffer.length < 4 # 2 for header, 2 for length

      buffer.byteslice(2, 2).unpack1('n')
    when 127
      return nil if buffer.length < 10 # 2 for header, 8 for length

      buffer.byteslice(2, 8).unpack1('Q>')
    else
      len_code
    end
  end

  def extract_payload(buffer, total_length, payload_length)
    @read_buffer.slice!(0, total_length)
    buffer.byteslice(-payload_length + total_length, payload_length)
  end

  def read_frame
    buffer = @read_buffer.dup
    return nil unless (header = parse_frame_header(buffer))

    fin, opcode, len_code = header
    return nil unless (payload_length = determine_payload_length(buffer, len_code))

    # p [fin, opcode, payload_length]

    total_length = 2 + payload_length
    total_length += 2 if len_code == 126
    total_length += 8 if len_code == 127

    return nil if buffer.length < total_length

    # p :matched_length

    payload = extract_payload(buffer, total_length, payload_length)
    [fin, opcode, payload]
  end

  def add_frame(fin, payload)
    @assembler.add_frame(fin, payload)
    return unless @assembler.complete_message?

    process_complete_message(@assembler.message?)
  end

  def process_frame(fin, opcode, payload)
    case opcode
    when 0x0, 0x1 then add_frame(fin, payload) # continuation frame or text frame
    when 0x8 then closed
    when 0x9 then send_pong
    else
      p([:unhandled_frame, opcode, payload])
      # Handle other opcodes (e.g., close, ping, pong) as needed
    end
  end

  def closed
    p(:ws_closed)
    exit
  end

  def process_complete_message(complete_message)
    @callback_proc_hash[:message]&.call(complete_message)
  end

  def retrieve_handshake
    handshake_response, @read_buffer = @read_buffer.split("\r\n\r\n", 2)
    status, *headers = handshake_response.split("\r\n")
    headers = headers.map { |e| e.split(': ', 2) }.to_h.transform_keys(&:downcase)
    headers['protocol'], headers['code'], headers['status'] = status.split(' ', 3).map(&:downcase)
    headers
  end
end

class WebSocketClient < Socket
  include SocketInterface
  include WebSocketIncomingMethods

  READ_LENGTH = 2048

  def initialize(url, callback_proc_hash)
    @uri = URI(url)
    @addrinfo = Addrinfo.getaddrinfo(@uri.host, @uri.port, nil, :STREAM).first
    super(@addrinfo.afamily, Socket::SOCK_STREAM, 0)
    @callback_proc_hash = callback_proc_hash
    init_defaults
    establish_connection
  end

  def send_message(message)
    @output_messages << message
    write_out
    nil
  end

  def close
    @callback_proc_hash[:disconnected]&.call
    super
  end

  private

  def establish_connection
    connect_nonblock(@addrinfo, exception: false)
    add_sock(method(:read_socket), self)
    handle_handshake
  end

  def init_defaults
    @assembler = WebSocketMessageAssembler.new
    @output_messages = []
    @write_buffer = ''.dup
    @read_buffer = ''.dup
    @connected = false
    @working_frame = ''.dup
  end

  def connected?
    return true if @connected
    return false unless @read_buffer.include?("\r\n\r\n")

    headers = retrieve_handshake
    @callback_proc_hash[:connected]&.call
    @connected = [headers['code'], headers['connection'], headers['upgrade']] == %w[101 upgrade websocket]
  end

  def slurp
    while (data = read)
      @read_buffer << data
    end
  end

  def read
    read_nonblock(READ_LENGTH)
  rescue IO::WaitReadable, Errno::EAGAIN
    nil
  end

  def read_socket(_sock)
    slurp
    # p([:read_from_ws, @read_buffer])
    return unless connected?

    while (frame = read_frame)
      # p [:while_framing, frame[0..100]]
      fin, opcode, payload = frame
      process_frame(fin, opcode, payload)
    end
  end

  def send_text(message)
    bytes = [129] # Text frame opcode
    size = message.bytesize

    bts = 125 if size <= 125
    bts = [126] + [size].pack('n').bytes if size < 2**16
    bts ||= [127] + [size].pack('Q>').bytes

    bytes += bts

    bytes += message.bytes
    bytes.pack('C*')
  end

  def handle_writeable
    next_message_to_output
    len = push_to_host
    return if len.zero?

    # p([:wrote, len])
    @write_buffer.slice!(0, len)
    remove_writeable(self, close: false) if empty?
  end

  def next_message_to_output
    return unless @write_buffer.empty?
    return if @output_messages.empty?

    @write_buffer = send_text(@output_messages.shift)
  end

  def push_to_host
    # p([:writing, @write_buffer])
    len = write_nonblock(@write_buffer)
  rescue IO::WaitWritable, Errno::EAGAIN => e
    p([:wrote_with_err, w, e])
    len.to_i
  end

  def handle_handshake
    @write_buffer = make_handshake
    write_out
  end

  def empty?
    @write_buffer.empty? && @output_messages.empty?
  end

  def make_handshake
    [
      "GET #{@uri.path} HTTP/1.1",
      "Host: #{@uri.host}:#{@uri.port}",
      'Upgrade: websocket',
      'Connection: Upgrade',
      "Origin: #{@uri.host}",
      'Sec-WebSocket-Key: sWlwf7JEB0szCFezxzsejA==', # Normally, this should be a new random key for each connection
      'Sec-WebSocket-Version: 13'
    ].join("\r\n") << "\r\n\r\n"
  end

  def send_pong
    # p :sending_pong
    @write_buffer ||= ''.dup
    @write_buffer << "\x8A\x00"
    write_out
  end

  def write_out
    return remove_writeable(self) if empty?

    add_writeable(method(:handle_writeable), self)
  end
end

# WebSocketClient.new(
#   'ws://127.0.0.1:8123/api/websocket',
#   { message: proc { |m| p([:handle_message, m]) } }
# )
# SelectController.instance.run
