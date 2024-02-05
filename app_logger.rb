# frozen_string_literal: true

require 'logger'

class AppLogger
  def self.setup(file_name)
    script_name = File.basename(file_name, '.*')
    log_path = "#{Dir.home('RPM')}/ruby/#{script_name}/"
    Dir.mkdir(log_path) unless Dir.exist?(log_path)

    # Use $0 to dynamically name the log file based on the script name
    log_filename = "#{log_path}#{script_name}_#{Time.now.strftime('%Y-%m-%d')}.log"

    logger = Logger.new(log_filename, 10, 1024 * 1024 * 10)
    logger.level = Logger::WARN
    logger
  end
end
