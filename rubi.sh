SCL='/Users/RPM/Applications/RacePointMedia/sclibridge'
[ -d '/Users' ] || SCL='/usr/local/bin/sclibridge'
CMDSTR='$0=%q[rubi];serv=TCPServer.open(%q[127.0.0.1],25809);loop{;io=serv.accept;f=fork {;$stderr = io;$stdout = io;@b||=binding;line_number=0;begin;while m=io.gets(%Q[\r\n]);eval(m,@b,%q[eval],line_number);line_number+=1;end;rescue=>e;p(e,e.backtrace);ensure;$stderr.reopen File.new(%q[/dev/null], %q[w]);end;};io.close;Process.detach(f);};'
GZN=$($SCL userzones | tr \\n \\0 | xargs -0 $SCL servicesforzone | grep GENERIC | head -n 1 | tr - \\n | head -n 1)
$($SCL settrigger rubi 2 Bool global SystemStatusIsRed Equal true State global CurrentMinute Equal global.CurrentMinute 0 "$GZN" "" "" 1 "SVC_GEN_GENERIC" "RunCLIProgram" "COMMAND_STRING" "ruby -r socket -e '$CMDSTR' 2>&1 /dev/null &")
echo "Start-up Trigger installed. Can be uninstalled with command 'sclibridge removetrigger rubi && sleep 5 && pkill -f rubi'"
pkill -f rubi

echo "Rubi Service will start within 1 minute."
