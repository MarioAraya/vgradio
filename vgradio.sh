#!/usr/bin/env bash
SESSION="vgradio"

tmux has-session -t "$SESSION" 2>/dev/null && { tmux attach -t "$SESSION"; exit 0; }

tmux new-session -d -s "$SESSION" -c ~/dev/vgradio-app/backend

# Panel 0 (izquierda): backend con claude
tmux send-keys -t "$SESSION":0.0 'claude' C-m

# Panel 1 (derecha arriba): web dev server
tmux split-window -h -t "$SESSION":0 -c ~/dev/vgradio-app/web
tmux send-keys -t "$SESSION":0.1 'npm run dev -- --host' C-m

# Panel 2 (derecha abajo): logs
tmux split-window -v -t "$SESSION":0.1 -c ~
tmux send-keys -t "$SESSION":0.2 'tail -f /tmp/vgradio.log' C-m

tmux select-pane -t "$SESSION":0.0
tmux attach -t "$SESSION"
