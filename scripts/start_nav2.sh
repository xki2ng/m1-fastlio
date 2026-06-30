#!/bin/bash
# ===== M1 Nav2 一键启动 (NX: 192.168.168.100) =====
# 前置: FAST-LIO 已运行 (提供 /Odometry + TF)
# 用法: bash /home/robot/fastlio/start_nav2.sh
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "========================================="
echo "  M1 Nav2 Navigator (FAST-LIO backend)"
echo "========================================="

# ---- 清理 ----
echo "[0/5] 清理旧进程..."
echo 1 | sudo -S killall -9 controller_server planner_server behavior_server \
    bt_navigator cmd_vel_flip odom_relay 2>/dev/null || true
sleep 2

source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0

# ---- 1. odom 中继 (FAST-LIO /Odometry → /odom/localization_odom) ----
echo "[1/5] odom 中继..."
nohup python3.10 $DIR/odom_relay.py > $DIR/logs/odom_relay.log 2>&1 &
echo "  PID: $!"

# ---- 2-5. Nav2 节点 (cmd_vel → /cmd_vel_raw, 避免与其他发布者冲突) ----
echo "[2/5] controller_server (DWB)..."
nohup ros2 run nav2_controller controller_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    -r /cmd_vel:=/cmd_vel_raw \
    > $DIR/logs/controller.log 2>&1 &

echo "[3/5] behavior_server..."
nohup ros2 run nav2_behaviors behavior_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    -r /cmd_vel:=/cmd_vel_raw \
    > $DIR/logs/behavior.log 2>&1 &

echo "[4/5] planner_server (Navfn)..."
nohup ros2 run nav2_planner planner_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    > $DIR/logs/planner.log 2>&1 &

echo "[5/5] bt_navigator..."
nohup ros2 run nav2_bt_navigator bt_navigator \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    > $DIR/logs/bt_navigator.log 2>&1 &

# ---- cmd_vel 翻转 ----
nohup python3.10 $DIR/cmd_vel_flip.py > $DIR/logs/cmd_vel_flip.log 2>&1 &
echo "  + cmd_vel_flip"

sleep 5

# ---- 激活 lifecycle ----
echo ""
echo "--- 激活 lifecycle ---"
for node in controller_server planner_server behavior_server bt_navigator; do
    ros2 lifecycle set /$node configure 2>/dev/null || true
    ros2 lifecycle set /$node activate 2>/dev/null || true
    echo -n "  $node: "
    ros2 lifecycle get /$node 2>/dev/null | head -1
done

echo ""
echo "=== 验证 ==="
NODES=$(ros2 node list --no-daemon 2>/dev/null | grep -cE "server|navigator|flip|relay")
echo "  Nav2 节点: $NODES"
echo ""
echo "发送导航目标:"
echo "  ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \\"
echo "    '{pose: {header: {frame_id: \"map\"}, pose: {position: {x: 2.0, y: 0.0}, orientation: {w: 1.0}}}}'"
echo ""
echo "停止 Nav2:"
echo "  sudo killall -9 controller_server planner_server behavior_server bt_navigator cmd_vel_flip odom_relay"
echo "========================================="
