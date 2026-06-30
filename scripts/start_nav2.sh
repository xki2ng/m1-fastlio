#!/bin/bash
# ===== M1 Nav2 一键启动 (NX: 192.168.168.100) =====
# 前置: FAST-LIO 已运行
# 自动检测并清理残留，确保唯一发布者
# 用法: bash /home/robot/fastlio/start_nav2.sh
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "========================================="
echo "  M1 Nav2 Navigator (FAST-LIO backend)"
echo "========================================="

# ---- 清理 ----
echo "[0/6] 清理残留..."
echo 1 | sudo -S killall -9 controller_server planner_server behavior_server \
    bt_navigator cmd_vel_flip odom_relay velocity_smoother 2>/dev/null || true

sleep 2
RESIDUAL=$(pgrep -f "controller_server|planner_server|behavior_server|bt_navigator|cmd_vel_flip|odom_relay" 2>/dev/null | wc -l)
if [ "$RESIDUAL" -gt 0 ]; then
    echo "  ⚠ 仍有 $RESIDUAL 个残留，强制清理..."
    echo 1 | sudo -S pkill -9 -f "controller_server|planner_server|behavior_server|bt_navigator|cmd_vel_flip|odom_relay" 2>/dev/null || true
    sleep 2
fi
echo "  ✓ 清理完成"

source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0

# ---- 1. odom 中继 ----
echo "[1/6] odom 中继 (/Odometry → /odom/localization_odom)..."
nohup python3.10 $DIR/odom_relay.py > $DIR/logs/odom_relay.log 2>&1 &
ODOM_PID=$!
sleep 1
if ! kill -0 $ODOM_PID 2>/dev/null; then
    echo "  ✗ 启动失败，查看 $DIR/logs/odom_relay.log"; exit 1
fi
echo "  PID: $ODOM_PID ✓"

# ---- 2-5. Nav2 节点 (cmd_vel → /cmd_vel_raw) ----
echo "[2/6] controller_server (DWB → /cmd_vel_raw)..."
nohup ros2 run nav2_controller controller_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    -r /cmd_vel:=/cmd_vel_raw \
    > $DIR/logs/controller.log 2>&1 &
echo "  PID: $!"

echo "[3/6] behavior_server (→ /cmd_vel_raw)..."
nohup ros2 run nav2_behaviors behavior_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    -r /cmd_vel:=/cmd_vel_raw \
    > $DIR/logs/behavior.log 2>&1 &
echo "  PID: $!"

echo "[4/6] planner_server (Navfn)..."
nohup ros2 run nav2_planner planner_server \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    > $DIR/logs/planner.log 2>&1 &
echo "  PID: $!"

echo "[5/6] bt_navigator..."
nohup ros2 run nav2_bt_navigator bt_navigator \
    --ros-args --params-file $DIR/m1_nav2_fastlio.yaml \
    > $DIR/logs/bt_navigator.log 2>&1 &
echo "  PID: $!"

# ---- cmd_vel 翻转 ----
nohup python3.10 $DIR/cmd_vel_flip.py > $DIR/logs/cmd_vel_flip.log 2>&1 &
echo "  + cmd_vel_flip PID: $!"

sleep 5

# ---- 激活 lifecycle ----
echo "[6/6] 激活 lifecycle..."
ALL_OK=true
for node in controller_server planner_server behavior_server bt_navigator; do
    ros2 lifecycle set /$node configure 2>/dev/null || true
    ros2 lifecycle set /$node activate 2>/dev/null || true
    STATE=$(ros2 lifecycle get /$node 2>/dev/null | head -1)
    if echo "$STATE" | grep -q "active"; then
        echo "  $node: ✓ ($STATE)"
    else
        echo "  $node: ✗ ($STATE)"
        ALL_OK=false
    fi
done

echo ""
echo "=== 验证 ==="
NODES=$(ros2 node list --no-daemon 2>/dev/null | grep -cE "server|navigator|flip|relay")
echo "  Nav2 节点: $NODES"

# 检查 costmap
if timeout 3 ros2 topic hz /local_costmap/costmap_raw 2>/dev/null | grep -q "average"; then
    echo "  local_costmap: ✓"
else
    echo "  local_costmap: ✗ (等待 LiDAR + TF 同步...)"
fi

# 检查 cmd_vel 发布者
PUB_COUNT=$(timeout 3 ros2 topic info /cmd_vel 2>/dev/null | grep "Publisher count" | awk '{print $3}')
echo "  /cmd_vel 发布者: $PUB_COUNT"

echo ""
if $ALL_OK; then
    echo "=== Nav2 启动成功 ==="
else
    echo "=== 部分节点激活失败，查看日志: $DIR/logs/ ==="
fi
echo ""
echo "发送导航目标:"
echo "  ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \\"
echo "    '{pose: {header: {frame_id: \"map\"}, pose: {position: {x: 2.0, y: 0.0}, orientation: {w: 1.0}}}}'"
echo ""
echo "停止: sudo killall -9 controller_server planner_server behavior_server bt_navigator cmd_vel_flip odom_relay"
echo "========================================="
