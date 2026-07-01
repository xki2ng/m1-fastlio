#!/bin/bash
# ===== M1 FAST-LIO 一键启动 (NX: 192.168.168.100) =====
# IMU旋转 + 全部TF已内置在 C++ 源码中，无需外部 Python/STP
# 用法: bash /home/robot/fastlio/start_fastlio.sh
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "========================================="
echo "  M1 FAST-LIO (Airy96, all-in-one C++)"
echo "========================================="

# ---- 清理 ----
echo "[0/2] 清理残留..."
echo 1 | sudo -S pkill -9 -f "localization_zg" 2>/dev/null || true
echo 1 | sudo -S pkill -9 -f "arc_lvio" 2>/dev/null || true
echo 1 | sudo -S pkill -9 -f "arc_mapping" 2>/dev/null || true
echo 1 | sudo -S pkill -9 -f "fastlio_mapping" 2>/dev/null || true
echo 1 | sudo -S killall -9 imu_rot static_transform_publisher 2>/dev/null || true
sleep 2
echo "  ✓ 清理完成"

# ---- 环境 ----
source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash 2>/dev/null || true
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0

# ---- FAST-LIO (IMU旋转 + TF 已内置) ----
echo "[1/2] FAST-LIO (IMU旋转+TF内置)..."
sleep 1
nohup ros2 run fast_lio fastlio_mapping \
    --ros-args --params-file $DIR/m1_airy96_rot.yaml \
    > $DIR/logs/fastlio.log 2>&1 &
FL_PID=$!
sleep 1
if ! kill -0 $FL_PID 2>/dev/null; then
    echo "  ✗ fastlio_mapping 启动失败，查看 $DIR/logs/fastlio.log"; exit 1
fi
echo "  PID: $FL_PID ✓"

# ---- 验证 ----
echo "[2/2] 验证..."
sleep 5
FAIL=0

if ros2 node list --no-daemon 2>/dev/null | grep -q laser_mapping; then
    echo "  laser_mapping: ✓"
else
    echo "  laser_mapping: ✗ (未出现)"
    FAIL=1
fi

if timeout 5 ros2 topic hz /Odometry 2>/dev/null | grep -q "average"; then
    echo "  /Odometry: ✓"
else
    echo "  /Odometry: ✗ (无数据)"
    FAIL=1
fi

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
