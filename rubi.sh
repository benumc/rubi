#!/bin/bash

# Helper function to detect sclibridge path
detect_scl() {
    if [ -f '/Users/Shared/Savant/Applications/RacePointMedia/sclibridge' ]; then
        echo '/Users/Shared/Savant/Applications/RacePointMedia/sclibridge'
    elif [ -f '/Users/RPM/Applications/RacePointMedia/sclibridge' ]; then
        echo '/Users/RPM/Applications/RacePointMedia/sclibridge'
    else
        echo '/usr/local/bin/sclibridge'
    fi
}

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
    SCL=$(detect_scl)
    
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
    
    # Remove duplicates, empty entries, and current script PID, then verify each PID
    RUBI_PIDS=""
    for pid in $ALL_PIDS; do
        if [ -n "$pid" ] && [ "$pid" != "$$" ]; then
            # Check if this PID is already in our list
            case " $RUBI_PIDS " in
                *" $pid "*) ;;  # Already in list
                *) 
                    # Verify this is actually a rubi-related process
                    if command -v ps >/dev/null 2>&1; then
                        # Use ps with different format options for better compatibility
                        CMD=$(ps -p "$pid" -o comm= 2>/dev/null | head -n1)
                        ARGS=$(ps -p "$pid" -o args= 2>/dev/null | head -n1)
                        if [ -n "$CMD" ] || [ -n "$ARGS" ]; then
                            # Check if it's a Ruby process running rubi server or has rubi title
                            if echo "$CMD $ARGS" | grep -q "ruby.*socket.*-e" || echo "$CMD $ARGS" | grep -q "^rubi" || echo "$CMD $ARGS" | grep -q "ruby.*rubi" || [ "$CMD" = "rubi" ]; then
                                RUBI_PIDS="$RUBI_PIDS $pid"
                                echo "Verified rubi process (PID $pid): $CMD $ARGS"
                            else
                                echo "Skipping unrelated process (PID $pid): $CMD $ARGS"
                            fi
                        fi
                    else
                        # Fallback if ps is not available
                        RUBI_PIDS="$RUBI_PIDS $pid"
                    fi
                    ;;
            esac
        fi
    done
    RUBI_PIDS=$(echo "$RUBI_PIDS" | sed 's/^ *//')  # Remove leading space
    
    if [ -n "$RUBI_PIDS" ]; then
        echo "Found rubi processes: $RUBI_PIDS"
        
        # Pre-elevate sudo privileges to avoid multiple password prompts
        if command -v sudo >/dev/null 2>&1; then
            sudo -v 2>/dev/null
        fi
        
        # Kill all PIDs in a single command to avoid multiple password prompts
        VALID_PIDS=""
        for pid in $RUBI_PIDS; do
            # Double-check this isn't our own script process
            if [ "$pid" != "$$" ] && [ -n "$pid" ]; then
                VALID_PIDS="$VALID_PIDS $pid"
            fi
        done
        VALID_PIDS=$(echo "$VALID_PIDS" | sed 's/^ *//')  # Remove leading space
        
        if [ -n "$VALID_PIDS" ]; then
            echo "Killing PIDs: $VALID_PIDS"
            if command -v sudo >/dev/null 2>&1; then
                sudo kill $VALID_PIDS 2>/dev/null || echo "Could not kill some processes"
            else
                kill $VALID_PIDS 2>/dev/null || echo "Could not kill some processes"
            fi
        fi
        
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
            if command -v sudo >/dev/null 2>&1; then
                sudo kill -9 $REMAINING 2>/dev/null || echo "Could not force kill some processes"
            else
                kill -9 $REMAINING 2>/dev/null || echo "Could not force kill some processes"
            fi
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
SCL=$(detect_scl)

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

# Find processes listening on port 25809 and processes with rubi title
PORT_PIDS=""
if command -v lsof >/dev/null 2>&1; then
    PORT_PIDS=$(lsof -ti:25809 2>/dev/null)
fi
TITLE_PIDS=$(pgrep -x rubi 2>/dev/null)
PATTERN_PIDS=$(pgrep -f "ruby.*socket.*-e\|rubi" 2>/dev/null | grep -v "^$$\$")

# Combine all PIDs
ALL_PIDS="$PORT_PIDS $TITLE_PIDS $PATTERN_PIDS"

# Collect unique PIDs, prioritizing port-based detection (most reliable)
RUBI_PIDS=""
for pid in $ALL_PIDS; do
    if [ -n "$pid" ] && [ "$pid" != "$$" ]; then
        # Check if this PID is already in our list
        case " $RUBI_PIDS " in
            *" $pid "*) ;;  # Already in list
            *) 
                # If this PID was found by port detection, it's definitely a rubi process
                case " $PORT_PIDS " in
                    *" $pid "*)
                        RUBI_PIDS="$RUBI_PIDS $pid"
                        echo "Found rubi process via port 25809 (PID $pid)"
                        ;;
                    *)
                        # For other PIDs, try to verify but be more lenient
                        if command -v ps >/dev/null 2>&1; then
                            # Use ps with different format options for better compatibility
                            CMD=$(ps -p "$pid" -o comm= 2>/dev/null | head -n1)
                            ARGS=$(ps -p "$pid" -o args= 2>/dev/null | head -n1)
                            if [ -n "$CMD" ] || [ -n "$ARGS" ]; then
                                # Check if it's a Ruby process running rubi server or has rubi title
                                FULL_CMD="$CMD $ARGS"
                                if echo "$FULL_CMD" | grep -q "ruby.*socket.*-e" || echo "$FULL_CMD" | grep -q "^rubi" || echo "$FULL_CMD" | grep -q "ruby.*rubi" || [ "$CMD" = "rubi" ]; then
                                    RUBI_PIDS="$RUBI_PIDS $pid"
                                    echo "Verified rubi process (PID $pid): $CMD $ARGS"
                                else
                                    # Only show skip message if we got reasonable output from ps
                                    if echo "$FULL_CMD" | grep -qv "^%cpu %mem" && [ ${#FULL_CMD} -lt 200 ]; then
                                        echo "Skipping unrelated process (PID $pid): $CMD $ARGS"
                                    fi
                                fi
                            fi
                        else
                            # Fallback if ps is not available - trust title-based detection
                            case " $TITLE_PIDS " in
                                *" $pid "*) 
                                    RUBI_PIDS="$RUBI_PIDS $pid"
                                    echo "Found rubi process via title (PID $pid)"
                                    ;;
                            esac
                        fi
                        ;;
                esac
                ;;
        esac
    fi
done
RUBI_PIDS=$(echo "$RUBI_PIDS" | sed 's/^ *//')  # Remove leading space

if [ -n "$RUBI_PIDS" ]; then
    echo "Found verified rubi processes: $RUBI_PIDS"
    for pid in $RUBI_PIDS; do
        echo "Killing PID $pid..."
        kill "$pid" 2>/dev/null || echo "Could not kill PID $pid"
    done
    sleep 1
    
    # Check if any are still running and force kill
    REMAINING=""
    for pid in $RUBI_PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            REMAINING="$REMAINING $pid"
        fi
    done
    
    if [ -n "$REMAINING" ]; then
        echo "Force killing remaining processes: $REMAINING"
        for pid in $REMAINING; do
            kill -9 "$pid" 2>/dev/null || echo "Could not force kill PID $pid"
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
# Export SCL path as environment variable for Ruby to use
export RUBI_SCL_PATH="$SCL"
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

  SCB = ENV[\"RUBI_SCL_PATH\"]
  system(\"#{SCB} writestate global.rubi 1\")
  
  Process.setproctitle(\"rubi\")
  
  def handle_client(client)
    pid = fork { exec(\"irb -f --noecho --noprompt\", :in=>client, :out=>client, :err=>client) }
    client.close
    Process.detach(pid) if pid
  end
  
  begin
    server = TCPServer.new(\"127.0.0.1\", 25809)
    server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
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