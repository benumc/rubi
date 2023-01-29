# rubi
Interactive ruby implementation for savant profiles.

Listens on 127.0.0.1 TCP port 25809

Runs code at each crlf while maintaining the current binding. 

RPM terminal will print errors and the profile will reconnect when errors are encoutered.

Install by opening a terminal connection to host and running the following command:

`bash <(curl -Ls "https://github.com/benumc/rubi/raw/main/rubi.sh")`

Uninstall by connecting the same way and running:

`sclibridge removetrigger rubi && sleep 5 && pkill -f rubi`

rubi based profiles should use the following control interfaces:
  <control_interfaces preferred="ip">
    <ip port="25809" response_time_length_ms="1000" protocol="tcp">
      <send_postfix type="hex">0D0A</send_postfix>
      <receive_end_condition test_condition="data" type="hex">0A</receive_end_condition>
    </ip>
  </control_interfaces>
  
All commands should be formatted as ruby instructions.
Any multi-line instrunction including large code blocks should be wrapped in standard <![CDATA[ ]]> tags.
It is very important that the document is formatted with line feeds only otherwise rubi will attempt to run every line as a complete instruction.

The generic_rubi.xml profile can be used to play with rubi using rpm terminal.

Commands can be sent to rubi for example: print(RUBY_VERSION)\h0D\h0A which will print the current ruby version. 
It is important to notice that we must explicitly request a print when we want data to be returned otherwise the command will run silently without output.

Unhandled standard errors will be rescued and printed. syntax errors will silently crash and the correction will re-initialize.

Blocking commands should be avoided until debugging is complete. It is probably better to fire a "myThread = Thread.new{some_code}" that can be killed "Thread.kill(my_thread)" if needed than to block the main thread as instructions will no longer be executed until the blocking code returns.

Don't use global variables $my_var use instance variables @my_var if you need to share values through your code.

I may not always reply right away, but please feel free to contact me on the Savant Programmers Slack chat if you have questions or issues.
