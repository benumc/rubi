SCL='/Users/RPM/Applications/RacePointMedia/sclibridge'
[ -d '/Users' ] || SCL='/usr/local/bin/sclibridge'
$($SCL removetrigger rubi)
sleep 2
pkill -f rubi
CMDSTR='cmd = %Q[ruby -r socket -e #{39.chr};$0 = %[rubi];serv = TCPServer.open(%[127.0.0.1], 25809);def eval_line(m, b, scope, line_number);eval(m, b, scope, line_number);rescue => e;$stderr.puts(e);end;def fork_proc(io,serv);f = fork do;serv.close;$stderr = io;$stdout = io;@b ||= binding;line_number = 0;while (m = io.gets(%Q[\\r\\n]));eval_line(m, @b, %q[eval], line_number);line_number += 1;end;end;io.close;Process.detach(f);end;def main_loop(serv);loop{;%x['$SCL' writestate global.rubi 1];io = serv.accept;fork_proc(io,serv);};ensure;%x['$SCL' writestate global.rubi 0];end;main_loop(serv);#{39.chr}];main_process = Process.spawn(cmd, %i[out err] => [%[/dev/null], %[w]]);Process.detach(main_process);'
GZN=$($SCL userzones | tr \\n \\0 | xargs -0 $SCL servicesforzone | grep GENERIC | head -n 1 | tr - \\n | head -n 1)
$($SCL settrigger rubi 2 State global CurrentMinute Equal global.CurrentMinute String global rubi "Not Equal" 1 0 "$GZN" "" "" 1 "SVC_GEN_GENERIC" "RunCLIProgram" "COMMAND_STRING" "ruby -r socket -e '$CMDSTR' 2>&1 /dev/null &")
$($SCL writestate global.rubi 2)
echo "Start-up Trigger installed. Can be uninstalled with command 'sclibridge removetrigger rubi && sleep 5 && pkill -f rubi'"
