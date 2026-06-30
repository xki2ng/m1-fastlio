#!/bin/bash
# ===== M1 FAST-LIO 一键启动 (NX: 192.168.168.100) =====
# 自动检测并清理残留，确保唯一发布者
# 用法: bash /home/robot/fastlio/start_fastlio.sh
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "========================================="
echo "  M1 FAST-LIO (Airy96 → LiDAR-IMU SLAM)"
echo "========================================="

# ---- 清理：杀掉所有可能冲突的残留进程 ----
echo "[0/4] 清理残留..."

# ARC domain 24 残留
echo 1 | sudo -S pkill -9 -f "localization_zg" 2>/dev/null || true
echo 1 | sudo -S pkill -9 -f "arc_lvio" 2>/dev/null || true
echo 1 | sudo -S pkill -9 -f "arc_mapping" 2>/dev/null || true

# 自己的旧进程
echo 1 | sudo -S killall -9 imu_rot fastlio_mapping 2>/dev/null || true
echo 1 | sudo -S killall -9 static_transform_publisher 2>/dev/null || true

# 确认清理
sleep 2
RESIDUAL=$(pgrep -f "fastlio_mapping|imu_rot" 2>/dev/null | wc -l)
if [ "$RESIDUAL" -gt 0 ]; then
    echo "  ⚠ 仍有 $RESIDUAL 个残留，强制清理..."
    echo 1 | sudo -S pkill -9 -f "fastlio_mapping|imu_rot" 2>/dev/null || true
    sleep 2
fi
echo "  ✓ 清理完成"

# ---- 环境 ----
source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash 2>/dev/null || true
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0
export ZENOH_SESSION_CONFIG_URI=$DIR/zenoh_nx_client.json5

# ---- 1. IMU 旋转 ----
echo "[1/4] IMU 旋转 (R_x(90°): Y上→Z上)..."
nohup python3.10 $DIR/imu_rot.py > $DIR/logs/imu_rot.log 2>&1 &
IMU_PID=$!
sleep 1
if ! kill -0 $IMU_PID 2>/dev/null; then
    echo "  ✗ imu_rot 启动失败，查看 $DIR/logs/imu_rot.log"; exit 1
fi
echo "  PID: $IMU_PID ✓"

# ---- 2. 静态 TF ----
echo "[2/4] 静态 TF (imu_link→body + imu_link→rslidar_head)..."
nohup ros2 run tf2_ros static_transform_publisher \
    -0.404 0 0.038 0 0 0 1 imu_link body \
    > $DIR/logs/tf_body.log 2>&1 &
nohup ros2 run tf2_ros static_transform_publisher \
    0 0 0 0 0.7071 0 0.7071 imu_link rslidar_head \
    > $DIR/logs/tf_rslidar.log 2>&1 &
echo "  ✓"

# ---- 3. FAST-LIO ----
echo "[3/4] FAST-LIO (lidar_type=5, Airy96)..."
sleep 2
nohup ros2 run fast_lio fastlio_mapping \
    --ros-args --params-file $DIR/m1_airy96_rot.yaml \
    > $DIR/logs/fastlio.log 2>&1 &
FL_PID=$!
sleep 1
if ! kill -0 $FL_PID 2>/dev/null; then
    echo "  ✗ fastlio_mapping 启动失败，查看 $DIR/logs/fastlio.log"; exit 1
fi
echo "  PID: $FL_PID ✓"

# ---- 4. 验证 ----
echo "[4/4] 验证..."
sleep 5
FAIL=0

# 检查节点
if ros2 node list --no-daemon 2>/dev/null | grep -q laser_mapping; then
    echo "  laser_mapping: ✓"
else
    echo "  laser_mapping: ✗ (未出现)"
    FAIL=1
fi

# 检查里程计
if timeout 5 ros2 topic hz /Odometry 2>/dev/null | grep -q "average"; then
    echo "  /Odometry: ✓"
else
    echo "  /Odometry: ✗ (无数据)"
    FAIL=1
fi

# 检查点云
if timeout 5 ros2 topic hz /cloud_registered_body 2>/dev/null | grep -q "average"; then
    echo "  /cloud_registered_body: ✓"
else
    echo "  /cloud_registered_body: ✗ (等待初始化...)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "=== FAST-LIO 启动成功 ==="
else
    echo "=== 部分检查失败，查看日志: $DIR/logs/ ==="
fi
echo "========================================="
