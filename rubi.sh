SCL='/Users/RPM/Applications/RacePointMedia/sclibridge'
[ -d '/Users' ] || SCL='/usr/local/bin/sclibridge'
$($SCL removetrigger rubi)
sleep 2
pkill -f rubi
GZN=$($SCL userzones | tr \\n \\0 | xargs -0 $SCL servicesforzone | grep GENERIC | head -n 1 | tr - \\n | head -n 1)
$($SCL settrigger rubi 2 State global CurrentMinute Equal global.CurrentMinute String global rubi "Not Equal" 1 0 "$GZN" "" "" 1 "SVC_GEN_GENERIC" "RunCLIProgram" "COMMAND_STRING" "ruby -r socket -e '
  SCB = %(#{RUBY_PLATFORM.include?(%(darwin))?%(/Users/RPM/Applications/RacePointMedia):%(/usr/local/bin)}/sclibridge)
  %x(#{SCB} writestate global.rubi 1)
  Process.daemon
  Process.setproctitle(%(rubi))
  def handle_client(c)
    pid=fork{exec(%(irb -f --noecho --noprompt),:in=>c,:out=>c,:err=>c)}
    c.close
    Process.kill(%(TERM),pid)if pid
    Process.wait(pid)if pid
  end
  begin
    server=TCPServer.new(%(127.0.0.1),25809)
    loop {handle_client(server.accept)}
  rescue=>e
    %x(#{SCB} writestate global.rubierror #{e.message.gsub(%( ), %(_))})
  ensure
    if server
      server.close
      %x(#{SCB} writestate global.rubi 0)
    end
  end
'")
$($SCL writestate global.rubi 2)
echo "Start-up Trigger installed. Can be uninstalled with command 'sclibridge removetrigger rubi && sleep 5 && pkill -f rubi'"
