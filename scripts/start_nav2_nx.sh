#!/bin/bash
# M1 Nav2 Navigation on FAST-LIO — start on NX (192.168.168.100)
# Launches each Nav2 node individually (no nav2_bringup required)
set -e
mkdir -p /tmp/nav2_logs

echo "=== M1 Nav2 Navigator (FAST-LIO backend) ==="
echo 1 | sudo -S killall -9 controller_server planner_server behavior_server bt_navigator velocity_smoother lifecycle_manager_nav 2>/dev/null || true
sleep 2

source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash 2>/dev/null || true
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0

NAV2_PARAMS=/tmp/m1_nav2_fastlio.yaml

# Launch nodes with params
echo "[1/5] Starting controller_server (DWB)..."
nohup ros2 run nav2_controller controller_server \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/controller.log 2>&1 &
echo "  PID: $!"

echo "[2/5] Starting planner_server (Navfn)..."
nohup ros2 run nav2_planner planner_server \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/planner.log 2>&1 &
echo "  PID: $!"

echo "[3/5] Starting behavior_server..."
nohup ros2 run nav2_behaviors behavior_server \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/behavior.log 2>&1 &
echo "  PID: $!"

echo "[4/5] Starting bt_navigator..."
nohup ros2 run nav2_bt_navigator bt_navigator \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/bt_navigator.log 2>&1 &
echo "  PID: $!"

echo "[5/5] Starting velocity_smoother..."
nohup ros2 run nav2_velocity_smoother velocity_smoother \
    --ros-args --params-file $NAV2_PARAMS \
    > /tmp/nav2_logs/velocity_smoother.log 2>&1 &
echo "  PID: $!"

sleep 5
source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=66 ROS_LOCALHOST_ONLY=0

# Activate lifecycle
echo ""
echo "--- Activating lifecycle ---"
for node in controller_server planner_server behavior_server bt_navigator velocity_smoother; do
    echo -n "  $node... "
    ros2 lifecycle set /$node configure 2>/dev/null && \
    ros2 lifecycle set /$node activate 2>/dev/null && echo "OK" || echo "SKIP"
    sleep 0.3
done

echo ""
echo "=== Verification ==="
NODES=$(ros2 node list --no-daemon 2>/dev/null | grep -cE "controller_server|planner_server|behavior_server|bt_navigator|velocity_smoother")
echo "  Nav2 nodes: $NODES (expect 5)"
echo "=== DONE ==="
echo ""
echo "To send a goal (2m forward):"
echo "  ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \\"
echo "    '{pose: {header: {frame_id: \"map\"}, pose: {position: {x: 2.0, y: 0.0}, orientation: {w: 1.0}}}}'"
echo ""
echo "To stop Nav2:"
echo "  sudo killall -9 controller_server planner_server behavior_server bt_navigator velocity_smoother"
