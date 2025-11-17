# rubi
Interactive ruby implementation for savant profiles.
Listens on 127.0.0.1 TCP port 25809
Runs code at each lf while maintaining the current binding. 
RPM terminal will print errors and the profile will reconnect when errors are encoutered.

Install by opening a terminal connection to host and running the following command:
bash <(curl -Ls "https://github.com/benumc/rubi/raw/main/rubi.sh")

Uninstall by connecting the same way and running:
sclibridge removetrigger rubi && sclibridge removetrigger rbwd && sleep 5 && pkill -f rubi

## Profile Types

### Rubi Profiles
rubi based profiles should use the following control interfaces:
  <control_interfaces preferred="ip">
    <ip port="25809" response_time_length_ms="1000" protocol="tcp">
      <send_postfix type="hex">0A</send_postfix>
      <receive_end_condition test_condition="data" type="hex">0A</receive_end_condition>
    </ip>
  </control_interfaces>

### Script Bridge Profile
The `benumc_script-bridge-rubi.xml` profile provides a drop-in replacement for existing script-bridge functionality to work with rubi co-processor. This allows existing script-based profiles to work with rubi without modification.

**Recent Enhancements:**
- **Cross-platform support**: Automatically detects correct Savant installation paths on both macOS and Linux
- **Robust port management**: Intelligent conflict resolution for port 25768 using multiple detection methods (lsof, netstat, process name matching)
- **Enhanced error handling**: Better logging and graceful failure recovery
- **Process cleanup**: Automatic cleanup of orphaned script bridge processes on startup
- **Standalone script**: Available as both embedded XML and standalone `script_bridge.rb` for development/debugging

**Usage:**
- Set Address on wire to 127.0.0.1
- Uses port 25768 for script bridge communication
- Automatically handles path detection and process management
- Compatible with existing script-based profiles

## Development

All commands should be formatted as ruby instructions.
Any multi-line instrunction including large code blocks should be wrapped in standard <![CDATA[ ]]> tags.

The generic_rubi.xml profile can be used to play with rubi using rpm terminal.

Commands can be sent to rubi for example: print(RUBY_VERSION)\h0A which will print the current ruby version. 

Blocking commands should be avoided until debugging is complete. It is probably better to fire a "myThread = Thread.new{some_code}" that can be killed "Thread.kill(my_thread)" if needed than to block the main thread as instructions will no longer be executed until the blocking code returns.

Don't use global variables $my_var use instance variables @my_var if you need to share values through your code.

## Files

- `script_bridge.rb` - Standalone version of the script bridge server (extracted from XML for easier development)
- `benumc_script-bridge-rubi.xml` - Complete profile with embedded script bridge functionality
- `rubi.sh` - Installation script
- Other XML profiles demonstrate various rubi implementations

## Support

I may not always reply right away, but please feel free to contact me on the Savant Programmers Slack chat if you have questions or issues.
