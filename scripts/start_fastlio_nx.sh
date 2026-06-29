#!/bin/bash
set -e
mkdir -p /tmp/fastlio

echo "=== NX FAST-LIO (raw PC + rotated IMU) ==="
echo 1 | sudo -S killall -9 imu_rot imu_scale imu_converter fastlio_mapping 2>/dev/null || true
sleep 2

source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0
export ZENOH_SESSION_CONFIG_URI=/tmp/zenoh_nx_client.json5

echo "[1/3] IMU rotation (R_x(90°): Y→Z up)..."
nohup python3.10 /tmp/imu_rot.py > /tmp/fastlio/imu_rot.log 2>&1 &
echo "  PID: $!"

echo "[2/3] Static TFs..."
nohup ros2 run tf2_ros static_transform_publisher -0.404 0 0.038 0 0 0 1 imu_link body > /tmp/fastlio/tf_body.log 2>&1 &
nohup ros2 run tf2_ros static_transform_publisher 0 0 0 0 0.7071 0 0.7071 imu_link rslidar_head > /tmp/fastlio/tf_rslidar.log 2>&1 &
echo "  done"

echo "[3/3] FAST-LIO..."
sleep 3
nohup ros2 run fast_lio fastlio_mapping --ros-args --params-file /tmp/m1_airy96_rot.yaml > /tmp/fastlio/fastlio.log 2>&1 &
FASTLIO_PID=$!
echo "  PID: $FASTLIO_PID"

sleep 6
source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=66 ROS_LOCALHOST_ONLY=0
echo "  Topics: $(ros2 topic list 2>/dev/null | wc -l)"
echo "=== DONE ==="
