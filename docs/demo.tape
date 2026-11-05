# ==============================================================================
# gamectl - Charm VHS Automated Terminal Demo Tape
# ==============================================================================
# Generate animated demo:
#   vhs docs/demo.tape
# ==============================================================================

# Output configuration
Output docs/demo.gif
Output docs/demo.mp4

# Terminal window styling
Set FontSize 14
Set FontFamily "JetBrains Mono"
Set Width 1200
Set Height 750
Set Padding 20
Set Theme "TokyoNight"
Set WindowBar "Colorful"
Set Framerate 60
Set PlaybackSpeed 1.0

# Pre-flight environment setup
Hide
Type "export TERM=xterm-256color" Enter
Type "export LANG=en_US.UTF-8" Enter
Type "cd $HOME/Projects/gamectl" Enter
Type "clear" Enter
Show

# Step 1: Version and Sovereign Identity
Type "gamectl --version" Sleep 300ms Enter
Sleep 1.5s
Type "clear" Enter

# Step 2: 7-Layer System & Hardware Health Audit
Type "gamectl doctor" Sleep 300ms Enter
Sleep 3s
Type "clear" Enter

# Step 3: Launch Interactive Master Dashboard Hub
Type "gamectl" Sleep 400ms Enter
Sleep 2s

# Navigate Hub modules
Down Sleep 600ms
Down Sleep 600ms
Up Sleep 600ms

# Open Module 1: Game Library
Enter Sleep 1.5s

# Browse library games & inspect split-pane preview cards
Sleep 1.5s
Down Sleep 800ms
Down Sleep 800ms
Up Sleep 800ms

# Return to Master Dashboard Hub
Escape Sleep 1s

# Exit gamectl cleanly
Escape Sleep 800ms

# Step 4: Show Instant Headless Launch Command
Type "gamectl launch ~/Games/DeadCells --hud --gamemode" Sleep 400ms
Sleep 2s
Ctrl+C
Sleep 1s
