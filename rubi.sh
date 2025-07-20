#!/bin/bash

# Check for command line arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: bash <(curl -Ls \"https://github.com/benumc/rubi/raw/main/rubi.sh\") [OPTION]"
    echo ""
    echo "Options:"
    echo "  (no args)         Install rubi IRB server triggers"
    echo "  --removetriggers  Remove rubi triggers and processes"
    echo "  --remove          Alias for --removetriggers"
    echo "  --help, -h        Show this help message"
    echo ""
    exit 0
fi

if [ "$1" = "--removetriggers" ] || [ "$1" = "--remove" ]; then
    echo "🗑️  REMOVING RUBI TRIGGERS"
    echo ""
    
    # Set up sclibridge path (same logic as installation)
    if [ -f '/Users/Shared/Savant/Applications/RacePointMedia/sclibridge' ]; then
        SCL='/Users/Shared/Savant/Applications/RacePointMedia/sclibridge'
    elif [ -f '/Users/RPM/Applications/RacePointMedia/sclibridge' ]; then
        SCL='/Users/RPM/Applications/RacePointMedia/sclibridge'
    else
        SCL='/usr/local/bin/sclibridge'
    fi
    
    echo "Using sclibridge at: $SCL"
    echo ""
    
    # Remove triggers
    echo "Removing 'rubi' trigger..."
    $SCL removetrigger rubi
    echo "✓ rubi trigger removed"
    echo ""
    
    echo "Removing 'rbwd' trigger..."
    $SCL removetrigger rbwd
    echo "✓ rbwd trigger removed"
    echo ""
    
    echo "Killing any existing rubi processes..."
    
    # Find processes listening on port 25809 (the IRB server port)
    PORT_PIDS=""
    if command -v lsof >/dev/null 2>&1; then
        PORT_PIDS=$(lsof -ti:25809 2>/dev/null)
    fi
    
    # Find processes with title "rubi" (from Process.setproctitle)
    TITLE_PIDS=$(pgrep -x rubi 2>/dev/null)
    
    # Combine all PIDs and remove current script PID
    ALL_PIDS="$PORT_PIDS $TITLE_PIDS"
    
    # Remove duplicates, empty entries, and current script PID
    RUBI_PIDS=""
    for pid in $ALL_PIDS; do
        if [ -n "$pid" ] && [ "$pid" != "$$" ]; then
            # Check if this PID is already in our list
            case " $RUBI_PIDS " in
                *" $pid "*) ;;  # Already in list
                *) RUBI_PIDS="$RUBI_PIDS $pid" ;;  # Add to list
            esac
        fi
    done
    RUBI_PIDS=$(echo "$RUBI_PIDS" | sed 's/^ *//')  # Remove leading space
    
    if [ -n "$RUBI_PIDS" ]; then
        echo "Found rubi processes: $RUBI_PIDS"
        for pid in $RUBI_PIDS; do
            # Double-check this isn't our own script process
            if [ "$pid" != "$$" ] && [ -n "$pid" ]; then
                echo "Killing PID $pid..."
                if command -v sudo >/dev/null 2>&1; then
                    sudo kill "$pid" 2>/dev/null || echo "Could not kill PID $pid"
                else
                    kill "$pid" 2>/dev/null || echo "Could not kill PID $pid"
                fi
            fi
        done
        
        # Give processes time to terminate gracefully
        sleep 2
        
        # Force kill any remaining processes
        REMAINING=$(pgrep -f "ruby.*rubi\|rubi.*ruby\|^rubi$\|irb.*25809" 2>/dev/null | grep -v "^$$\$")
        if command -v lsof >/dev/null 2>&1; then
            REMAINING_PORT=$(lsof -ti:25809 2>/dev/null)
            if [ -n "$REMAINING_PORT" ]; then
                REMAINING="$REMAINING $REMAINING_PORT"
            fi
        fi
        REMAINING=$(echo "$REMAINING" | tr ' ' '\n' | sort -u | grep -v "^$\|^$$\$" | tr '\n' ' ')
        
        if [ -n "$REMAINING" ]; then
            echo "Force killing remaining processes: $REMAINING"
            for pid in $REMAINING; do
                if [ "$pid" != "$$" ] && [ -n "$pid" ]; then
                    if command -v sudo >/dev/null 2>&1; then
                        sudo kill -9 "$pid" 2>/dev/null || echo "Could not force kill PID $pid"
                    else
                        kill -9 "$pid" 2>/dev/null || echo "Could not force kill PID $pid"
                    fi
                fi
            done
        fi
    else
        echo "No rubi processes found"
    fi
    echo "✓ Process cleanup completed"
    echo ""
    
    echo "🎉 Rubi triggers successfully removed!"
    exit 0
fi

# Set up sclibridge path
if [ -f '/Users/Shared/Savant/Applications/RacePointMedia/sclibridge' ]; then
    SCL='/Users/Shared/Savant/Applications/RacePointMedia/sclibridge'
elif [ -f '/Users/RPM/Applications/RacePointMedia/sclibridge' ]; then
    SCL='/Users/RPM/Applications/RacePointMedia/sclibridge'
else
    SCL='/usr/local/bin/sclibridge'
fi

echo "Using sclibridge at: $SCL"
echo ""

# Remove existing triggers
echo "Removing existing 'rbwd' trigger..."
$SCL removetrigger rbwd
echo "✓ rbwd trigger removal completed"
echo ""

echo "Removing existing 'rubi' trigger..."
$SCL removetrigger rubi
echo "✓ rubi trigger removal completed"
echo ""

echo "Waiting 2 seconds for cleanup..."
sleep 2
echo ""

echo "Killing any existing rubi processes..."
# Find rubi processes but exclude this script (bash process)
RUBI_PIDS=$(pgrep -f "ruby.*rubi\|rubi.*ruby" 2>/dev/null | grep -v "^$$\$")
if [ -n "$RUBI_PIDS" ]; then
    echo "Found rubi processes: $RUBI_PIDS"
    for pid in $RUBI_PIDS; do
        # Double-check this isn't our own script process
        if [ "$pid" != "$$" ]; then
            echo "Killing PID $pid..."
            kill "$pid" 2>/dev/null || echo "Could not kill PID $pid"
        fi
    done
    sleep 1
    # Check if any are still running and force kill
    REMAINING=$(pgrep -f "ruby.*rubi\|rubi.*ruby" 2>/dev/null | grep -v "^$$\$")
    if [ -n "$REMAINING" ]; then
        echo "Force killing remaining processes: $REMAINING"
        for pid in $REMAINING; do
            if [ "$pid" != "$$" ]; then
                kill -9 "$pid" 2>/dev/null || echo "Could not force kill PID $pid"
            fi
        done
    fi
else
    echo "No rubi processes found"
fi
echo "✓ Process cleanup completed"
echo ""

echo "Getting generic zone name..."
GZN=$($SCL userzones | tr \\n \\0 | xargs -0 $SCL servicesforzone | grep GENERIC | head -n 1 | tr - \\n | head -n 1)
echo "✓ Found generic zone: $GZN"
echo ""

echo "Setting up 'rbwd' (Ruby Watchdog) trigger..."
# This trigger checks if the rubi server is running and starts it if needed
$SCL settrigger rbwd 1 State global CurrentMinute Equal global.CurrentMinute 0 "$GZN" "" "" 1 "SVC_GEN_GENERIC" "RunCLIProgram" "COMMAND_STRING" "lsof -i :25809 || $SCL writestate global.rubi 1 global.rubi 0"
echo "✓ rbwd trigger setup completed"
echo ""

echo "Setting up 'rubi' trigger..."
# This trigger starts the Ruby IRB server when global.rubi changes to 1
$SCL settrigger rubi 1 String global rubi "Not Equal" 1 0 "$GZN" "" "" 1 "SVC_GEN_GENERIC" "RunCLIProgram" "COMMAND_STRING" "ruby -r socket -e '
fork do
  Process.setsid
  exit if fork
  STDIN.reopen(\"/dev/null\")
  STDOUT.reopen(\"/dev/null\", \"a\")
  STDERR.reopen(\"/dev/null\", \"a\")
  
  # Close all file descriptors except standard ones
  fd_max = Process.getrlimit(:NOFILE)[0]
  3.upto(fd_max) do |i|
    begin
      IO.for_fd(i).close
    rescue Errno::EBADF, ArgumentError
    end
  end

  SCB = if RUBY_PLATFORM.include?(\"darwin\")
    if File.exist?(\"/Users/Shared/Savant/Applications/RacePointMedia/sclibridge\")
      \"/Users/Shared/Savant/Applications/RacePointMedia/sclibridge\"
    elsif File.exist?(\"/Users/RPM/Applications/RacePointMedia/sclibridge\")
      \"/Users/RPM/Applications/RacePointMedia/sclibridge\"
    else
      \"/usr/local/bin/sclibridge\"
    end
  else
    \"/usr/local/bin/sclibridge\"
  end
  system(\"#{SCB} writestate global.rubi 1\")
  
  Process.daemon
  Process.setproctitle(\"rubi\")
  
  def handle_client(client)
    pid = fork { exec(\"irb -f --noecho --noprompt\", :in=>client, :out=>client, :err=>client) }
    client.close
    Process.detach(pid) if pid
  end
  
  begin
    server = TCPServer.new(\"127.0.0.1\", 25809)
    loop { handle_client(server.accept) }
  rescue => e
    system(\"#{SCB} writestate global.rubierror #{e.message.gsub(\" \", \"_\")}\")
  ensure
    if server
      server.close
      system(\"#{SCB} writestate global.rubi 0\")
    end
  end
end
' &"
echo "✓ rubi trigger setup completed"
echo ""

echo "Initializing rubi state..."
$SCL writestate global.rubi 2
echo "✓ rubi state initialized to 2"
echo ""

echo "🎉 Rubi IRB Server triggers installed successfully!"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Install the M2 or Benumc Script Bridge v2 Profile in your Savant configuration"
echo "2. Install any other profiles (like Ezlo Hub) that contain scripts after the 'splitScript' marker"
echo "3. The M2 or Benumc Script Bridge will listen on port 25768 and execute profile scripts"
echo "4. The Rubi IRB server will run on port 25809 for interactive Ruby sessions"
echo ""
echo "📝 To uninstall: bash <(curl -Ls \"https://github.com/benumc/rubi/raw/main/rubi.sh\") --removetriggers"