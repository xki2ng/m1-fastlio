# M1 FAST-LIO (All-in-One C++)

FAST-LIO GPU SLAM for M1 quadruped robot with RoboSense Airy96 LiDAR.

**Key changes from upstream:**
- **IMU rotation built-in**: R_x(90°) applied in `imu_cbk`, no external Python script needed
- **TF self-contained**: Static transforms (`imu_link→body`, `imu_link→rslidar_head`, `map→odom`) broadcast via `StaticTransformBroadcaster` in C++
- **No hardcoded TF override**: Removed per-frame `rslidar_head→body` broadcast that conflicted with proper sensor mounting TFs
- **Direct LiDAR/IMU**: Reads `/front_lidar` and `/front_lidar/imu` from rslidar_sdk directly

## Architecture

```
/front_lidar → FAST-LIO (IMU R_x(90°) built-in)
/front_lidar/imu → FAST-LIO
         ↓
  /Odometry + odom→imu_link TF (10Hz)
  /cloud_registered + /Laser_map
         ↓
  Static TFs: imu_link→body [-0.404,0,0.038], imu_link→rslidar_head R_y(+90°)
```

## TF Tree

```
map → odom              (static identity)
odom → imu_link         (FAST-LIO dynamic)
imu_link → body         (static, LiDAR mount offset)
imu_link → rslidar_head (static, R_y(+90°) orientation)
```

## Quick Start

```bash
bash start_fastlio.sh
```

## Config

See `config.yaml` for LiDAR/IMU topics, frame names, and SLAM parameters.
