#!/bin/bash
# ===== M1 FAST-LIO 一键启动 (NX: 192.168.168.100) =====
# 用法: bash /home/robot/fastlio/start_fastlio.sh
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "========================================="
echo "  M1 FAST-LIO (Airy96 -> LiDAR-IMU SLAM)"
echo "========================================="

# ---- 清理 ----
echo "[0/3] 清理旧进程..."
echo 1 | sudo -S pkill -9 -f "localization_zg|arc_lvio|arc_mapping" 2>/dev/null || true
echo 1 | sudo -S killall -9 imu_rot fastlio_mapping 2>/dev/null || true
sleep 2

# ---- 环境 ----
source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash 2>/dev/null || true
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0
export ZENOH_SESSION_CONFIG_URI=$DIR/zenoh_nx_client.json5

# ---- 1. IMU 旋转 ----
echo "[1/3] IMU 旋转 (R_x(90°): Y上→Z上)..."
nohup python3.10 $DIR/imu_rot.py > $DIR/logs/imu_rot.log 2>&1 &
echo "  PID: $!"

# ---- 2. 静态 TF ----
echo "[2/3] 静态 TF..."
nohup ros2 run tf2_ros static_transform_publisher \
    -0.404 0 0.038 0 0 0 1 imu_link body \
    > $DIR/logs/tf_body.log 2>&1 &
nohup ros2 run tf2_ros static_transform_publisher \
    0 0 0 0 0.7071 0 0.7071 imu_link rslidar_head \
    > $DIR/logs/tf_rslidar.log 2>&1 &
echo "  imu_link → body + rslidar_head"

# ---- 3. FAST-LIO ----
echo "[3/3] FAST-LIO (lidar_type=5, Airy96)..."
sleep 3
nohup ros2 run fast_lio fastlio_mapping \
    --ros-args --params-file $DIR/m1_airy96_rot.yaml \
    > $DIR/logs/fastlio.log 2>&1 &
echo "  PID: $!"

sleep 5
echo ""
echo "=== 验证 ==="
echo -n "  laser_mapping: "
ros2 node list --no-daemon 2>/dev/null | grep -q laser_mapping && echo "✓" || echo "✗"
echo -n "  /Odometry: "
timeout 3 ros2 topic hz /Odometry 2>/dev/null | grep -q "average" && echo "✓" || echo "✗"
echo ""
echo "日志: $DIR/logs/"
echo "========================================="
