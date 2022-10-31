# rubi
Interactive ruby implementation for savant profiles.

Listens on 127.0.0.1 TCP port 25802

Runs code at each crlf while maintaining the current binding. 

RPM terminal will print errors and the profile will reconnect when errors are encoutered.

Install by opening a terminal connection to host and running the following command:

`bash <(curl -Ls "https://github.com/benumc/rubi/raw/main/rubi.sh")`

Uninstall by connecting the same way and running:

`sclibridge removetrigger rubi && sleep 5 && pkill -f rubi'`
