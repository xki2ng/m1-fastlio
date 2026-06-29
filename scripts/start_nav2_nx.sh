#!/bin/bash
# M1 Nav2 Navigation on FAST-LIO — unified start script for NX
# Prerequisites: FAST-LIO already running, robot_forward running
set -e
mkdir -p /tmp/nav2_logs

echo "=== M1 Nav2 Navigator (FAST-LIO backend) ==="

# ---- Cleanup ----
echo "[0] Cleaning old processes..."
echo 1 | sudo -S killall -9 controller_server planner_server behavior_server \
    bt_navigator cmd_vel_flip odom_relay 2>/dev/null || true
sleep 2

source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0

NAV2_PARAMS=/tmp/m1_nav2_fastlio.yaml

# ---- Step 1: odom_relay (FAST-LIO/Odometry → /odom/localization_odom) ----
echo "[1] Starting odom relay..."
nohup python3.10 /tmp/odom_relay.py > /tmp/odom_relay.log 2>&1 &

# ---- Step 2: Nav2 nodes (all remapped to /cmd_vel_raw) ----
echo "[2] Starting controller_server (→ /cmd_vel_raw)..."
nohup ros2 run nav2_controller controller_server \
    --ros-args --params-file $NAV2_PARAMS \
    -r /cmd_vel:=/cmd_vel_raw \
    > /tmp/nav2_logs/controller_server.log 2>&1 &

echo "[3] Starting behavior_server (→ /cmd_vel_raw)..."
nohup ros2 run nav2_behaviors behavior_server \
    --ros-args --params-file $NAV2_PARAMS \
    -r /cmd_vel:=/cmd_vel_raw \
    > /tmp/nav2_logs/behavior_server.log 2>&1 &

echo "[4] Starting planner_server..."
nohup ros2 run nav2_planner planner_server \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/planner_server.log 2>&1 &

echo "[5] Starting bt_navigator..."
nohup ros2 run nav2_bt_navigator bt_navigator \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/bt_navigator.log 2>&1 &

# ---- Step 3: cmd_vel_flip (/cmd_vel_raw → flipped → /cmd_vel) ----
echo "[6] Starting cmd_vel_flip..."
nohup python3.10 /tmp/cmd_vel_flip.py > /tmp/cmd_vel_flip.log 2>&1 &

sleep 5

# ---- Step 4: Lifecycle activation ----
echo "[7] Activating lifecycle..."
for node in controller_server planner_server behavior_server bt_navigator; do
    ros2 lifecycle set /$node configure 2>/dev/null || true
    ros2 lifecycle set /$node activate 2>/dev/null || true
    echo "  $node: $(ros2 lifecycle get /$node 2>/dev/null | head -1)"
done

echo ""
echo "=== Verification ==="
NODES=$(ros2 node list --no-daemon 2>/dev/null | grep -cE "server|navigator|flip|relay")
echo "  Nav2 nodes: $NODES"

echo ""
echo "=== DONE ==="
echo ""
echo "To send a navigation goal:"
echo "  ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \\"
echo "    '{pose: {header: {frame_id: \"map\"}, pose: {position: {x: X, y: Y}, orientation: {w: 1.0}}}}'"
echo ""
echo "To stop Nav2:"
echo "  sudo killall -9 controller_server planner_server behavior_server bt_navigator cmd_vel_flip"
