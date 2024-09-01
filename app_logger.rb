# frozen_string_literal: true

require 'logger'
require 'fileutils'

class AppLogger
  def self.setup(file_name, log_path = Dir.home)
    script_name = File.basename(file_name, '.*')
    log_path = "#{log_path.chomp('/')}/#{script_name}/"
    FileUtils.mkdir_p(log_path) unless Dir.exist?(log_path)

    log_filename = "#{log_path}#{script_name}_#{Time.now.strftime('%Y-%m-%d')}.log"

    logger = Logger.new(log_filename, 10, 1024 * 1024 * 10)
    logger.level = Logger::WARN
    logger
  end
end
