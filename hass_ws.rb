# frozen_string_literal: true

require 'logger'
require 'json'

require_relative 'app_logger'

HASS_DIRECTORY_PATH = "#{Dir.home('RPM')}/home_assistant/" unless defined?(HASS_DIRECTORY_PATH)
LOG = AppLogger.setup(__FILE__, HASS_DIRECTORY_PATH) unless defined?(LOG)
LOG.level = Logger::DEBUG

require_relative 'select_controller'
require_relative 'non_blocking_ws_client'

module HassMessageParsingMethods
  def new_data(js_data)
    return {} unless js_data['data']

    js_data['data']['new_state'] || js_data['data']
  end

  def parse_event(js_data)
    return entities_changed(js_data['c']) if js_data.keys == ['c']
    return entities_changed(js_data['a']) if js_data.keys == ['a']

    case js_data['event_type']
    when 'state_changed' then parse_state(new_data(js_data))
    when 'call_service' then parse_service(new_data(js_data))
    else
      [:unknown, js_data['event_type']]
    end
  end

  def entities_changed(entities)
    entities.each do |entity, state|
      state = state['+'] if state.key?('+')
      LOG.debug([:changed, entity, state])
      attributes = state['a']
      value = state['s']
      update?("#{entity}_state", 'state', value) if value
      update_with_hash(entity, attributes) if attributes
    end
  end

  def parse_service(data)
    return [] unless data['service_data'] && data['service_data']['entity_id']

    [data['service_data']['entity_id']].flatten.compact.map do |entity|
      "type:call_service,entity:#{entity},service:#{data['service']},domain:#{data['domain']}"
    end
  end

  def included_with_filter?(primary_key)
    return true if @filter.empty? || @filter == ['all']

    @filter.include?(primary_key)
  end

  def parse_state(message)
    eid = message['entity_id']

    update?("#{eid}_state", 'state', message['state']) if eid

    atr = message['attributes']
    case atr
    when Hash then update_with_hash(eid, atr)
    when Array then update_with_array(eid, atr)
    end
  end

  def update?(key, primary_key, value)
    return unless value && included_with_filter?(primary_key)

    value = 3 if primary_key == 'brightness' && [1, 2].include?(value)

    to_savant("#{key}===#{value}")
  end

  def update_hashed_array(parent_key, msg_array)
    msg_array.each_with_index do |e, i|
      key = "#{parent_key}_#{i}"
      case e
      when Hash then update_with_hash(key, e)
      when Array then update_with_array(key, e)
      else
        update?(key, i, e)
      end
    end
  end

  def update_with_array(parent_key, msg_array)
    return update_hashed_array(parent_key, msg_array) if msg_array.first.is_a?(Hash)

    update?(parent_key, parent_key, msg_array.join(','))
  end

  def update_with_hash(parent_key, msg_hash)
    arr = msg_hash.map do |k, v|
      update?("#{parent_key}_#{k}", k, v) if included_with_filter?(k)
      "#{k}:#{v}"
    end
    return unless included_with_filter?('attributes')

    update?("#{parent_key}_attributes", parent_key, arr.join(','))
  end

  def parse_result(js_data)
    LOG.debug([:jsdata, js_data])
    res = js_data['result']
    return unless res

    LOG.debug([:parsing, res.length])
    return parse_state(res) unless res.is_a?(Array)

    res.each do |e|
      LOG.debug([:parsing, e.length, e.keys])
      parse_state(e)
    end
  end
end

module HassRequests
  def fan_on(entity_id, speed)
    send_data(
      type: :call_service, domain: :fan, service: :turn_on,
      service_data: { speed: speed },
      target: { entity_id: entity_id }
    )
  end

  def fan_off(entity_id, _speed)
    send_data(
      type: :call_service, domain: :fan, service: :turn_off,
      target: { entity_id: entity_id }
    )
  end

  def fan_set(entity_id, speed)
    speed.to_i.zero? ? fan_off(entity_id) : fan_on(entity_id, speed)
  end

  def switch_on(entity_id)
    send_data(
      type: :call_service, domain: :light, service: :turn_on,
      target: { entity_id: entity_id }
    )
  end

  def switch_off(entity_id)
    send_data(
      type: :call_service, domain: :light, service: :turn_off,
      target: { entity_id: entity_id }
    )
  end

  def dimmer_on(entity_id, level)
    send_data(
      type: :call_service, domain: :light, service: :turn_on,
      service_data: { brightness_pct: level },
      target: { entity_id: entity_id }
    )
  end

  def dimmer_off(entity_id)
    send_data(
      type: :call_service, domain: :light, service: :turn_off,
      target: { entity_id: entity_id }
    )
  end

  def dimmer_set(entity_id, level)
    level.to_i.zero? ? dimmer_off(entity_id) : dimmer_on(entity_id, level)
  end

  def shade_set(entity_id, level)
    send_data(
      type: :call_service, domain: :cover, service: :set_cover_position,
      service_data: { position: level },
      target: { entity_id: entity_id }
    )
  end

  def lock_lock(entity_id)
    send_data(
      type: :call_service, domain: :lock, service: :lock,
      target: { entity_id: entity_id }
    )
  end

  def unlock_lock(entity_id)
    send_data(
      type: :call_service, domain: :lock, service: :unlock,
      target: { entity_id: entity_id }
    )
  end

  def open_garage_door(entity_id)
    send_data(
      type: :call_service, domain: :cover, service: :open_cover,
      target: { entity_id: entity_id }
    )
  end

  def close_garage_door(entity_id)
    send_data(
      type: :call_service, domain: :cover, service: :close_cover,
      target: { entity_id: entity_id }
    )
  end
end

class Hass
  include HassMessageParsingMethods
  include HassRequests

  POSTFIX = "\n"

  def initialize(hass_address, token, filter = ['all'])
    LOG.debug [:connecting_to, hass_address]
    @address = hass_address
    @token = token
    @filter = filter
    @out_buf = []
    @ping_proc = proc { send_ping }
    @print_proc = proc { next_buf }

    connect_websocket
  end

  def subscribe_entity(*entity_id)
    send_json(
      type: 'subscribe_entities',
      entity_ids: entity_id.flatten
    )
    send_json(type: 'subscribe_events') if HASS_SUBSCRIBE_ALL_EVENTS
  end

  def send_data(**data)
    LOG.debug(data)
    send_json(data)
  end

  private

  def connect_websocket
    @id = 0
    proc_hash = {
      connect: @ping_proc,
      disconnect: proc { p(:ws_disconnected) },
      message: proc { |message| handle_message(message) }
    }
    @hass_ws = WebSocketClient.new("ws://#{@address}/api/websocket", proc_hash)
    SelectController.instance.stdin_proc = proc { |req| from_savant(req) }
  end

  def from_savant(req)
    cmd, *params = req.split(',')
    return send(cmd, *params) if respond_to?(cmd)

    p([:unknown_cmd, cmd, req])
  end

  def send_ping
    p(:ws_connected)
    add_timeout
  end

  def handle_message(data)
    # puts data
    return unless (message = JSON.parse(data))
    return LOG.error([:request_failed, message]) if message['success'] == false

    LOG.debug([:handling, message])
    handle_hash(message)
  end

  def handle_hash(message)
    # puts message
    case message['type']
    when 'auth_required' then send_auth
    when 'event' then parse_event(message['event'])
    when 'result' then parse_result(message)
    when 'pong' then 'pong'
    end
  end

  def send_auth
    @hass_ws.send_message({ type: 'auth', access_token: @token }.to_json)
  end

  def send_json(hash)
    @id += 1
    hash['id'] = @id
    LOG.debug([:send, hash])
    @hass_ws.send_message(hash.to_json)
  end

  def to_savant(*message)
    return unless message

    print(map_message(message).join)
  end

  def map_message(message)
    Array(message).map do |m|
      next unless m

      [m.to_s.gsub(POSTFIX, ''), POSTFIX]
    end
  end

  def next_buf
    print(@out_buf.shift)
    timeout!(@print_proc, 0.005) unless @out_buf.empty?
  end
end
