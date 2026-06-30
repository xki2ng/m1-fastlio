#!/bin/bash
# M1 FAST-LIO startup for NX — permanent paths, auto-kill ARC conflicts
set -e
DIR=/home/robot/fastlio
mkdir -p $DIR/logs

echo "=== NX FAST-LIO (pid $$) ==="

# Kill ARC localization (might have respawned)
echo 1 | sudo -S killall -9 arc_lvio arc_lvio_node arc_mapping arc_mapping_node localization_zg 2>/dev/null || true
echo 1 | sudo -S killall -9 imu_rot fastlio_mapping 2>/dev/null || true
sleep 2

source /opt/ros/humble/setup.bash
source /home/robot/m1_ws/install/setup.bash 2>/dev/null || true
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0
export ZENOH_SESSION_CONFIG_URI=$DIR/zenoh_nx_client.json5

echo "[1/3] IMU rotation (R_x(90°): Y→Z up)..."
nohup python3.10 $DIR/imu_rot.py > $DIR/logs/imu_rot.log 2>&1 &
echo "  PID: $!"

echo "[2/3] Static TFs..."
nohup ros2 run tf2_ros static_transform_publisher -0.404 0 0.038 0 0 0 1 imu_link body > $DIR/logs/tf_body.log 2>&1 &
nohup ros2 run tf2_ros static_transform_publisher 0 0 0 0 0.7071 0 0.7071 imu_link rslidar_head > $DIR/logs/tf_rslidar.log 2>&1 &
echo "  done"

echo "[3/3] FAST-LIO..."
sleep 3
nohup ros2 run fast_lio fastlio_mapping --ros-args --params-file $DIR/m1_airy96_rot.yaml > $DIR/logs/fastlio.log 2>&1 &
FASTLIO_PID=$!
echo "  PID: $FASTLIO_PID"

sleep 5
echo "=== DONE ==="
echo "  Logs: $DIR/logs/"
