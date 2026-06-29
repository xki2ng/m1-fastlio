# M1 FAST-LIO — Jetson Orin NX Deployment

GPU-accelerated FAST-LIO2 for the Genisom M1 quadruped robot with RoboSense Airy96 LiDAR.  
Deployed on **Jetson Orin NX (192.168.168.100)** with Zenoh DDS for cross-machine communication.

## Architecture

```
┌─ M1 Main Controller (192.168.168.168) ───────────────────┐
│  rslidar_sdk                                              │
│    ├─ /front_lidar     (PointCloud2, raw, 10 Hz)          │
│    └─ /front_lidar/imu (Imu, Y-up, g-units, 100 Hz)      │
│                                                           │
│  Zenoh Router :7447                                       │
└────────────────────────────────┬──────────────────────────┘
                                 │ Zenoh DDS (domain 66)
                                 │
┌─ Jetson Orin NX (192.168.168.100) ────────────────────────┐
│  imu_rot.py   (R_x(90°): Y→Z gravity)                    │
│    /front_lidar/imu → /livox/imu                         │
│                                                           │
│  static_tf x2                                             │
│    imu_link → body       (-0.404, 0, 0.038)              │
│    imu_link → rslidar_head (R_y(90°))                     │
│                                                           │
│  fastlio_mapping                                          │
│    LiDAR: /front_lidar      (direct)                      │
│    IMU:   /livox/imu        (rotated)                     │
│    Odometry:  /Odometry     (odom→imu_link, ~10 Hz)       │
│    Map:       /Laser_map    (point cloud map)             │
└───────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- M1 robot powered on, LiDAR spinning
- Jetson Orin NX running ROS2 Humble
- `rslidar_sdk` publishing `/front_lidar` and `/front_lidar/imu`
- Zenoh router running on both M1 controller (:7447) and NX (:7447)

### One-Command Deploy

```bash
# On your workstation (192.168.168.50 or any machine with SSH to NX):
sshpass -p '1' scp scripts/imu_rot.py scripts/m1_airy96_rot.yaml \
    scripts/zenoh_nx_client.json5 scripts/start_fastlio_nx.sh \
    robot@192.168.168.100:/tmp/

sshpass -p '1' ssh robot@192.168.168.100 'bash /tmp/start_fastlio_nx.sh'
```

### Manual Step-by-Step

```bash
# 1. SSH to NX
ssh robot@192.168.168.100

# 2. Source ROS2
source /opt/ros/humble/setup.bash
source ~/m1_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ROS_DOMAIN_ID=66
export ROS_LOCALHOST_ONLY=0
export ZENOH_SESSION_CONFIG_URI=/tmp/zenoh_nx_client.json5

# 3. Kill old processes
sudo killall -9 imu_rot fastlio_mapping 2>/dev/null

# 4. Start IMU rotation
python3.10 /tmp/imu_rot.py &

# 5. Start static TF publishers
ros2 run tf2_ros static_transform_publisher -0.404 0 0.038 0 0 0 1 imu_link body &
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0.7071 0 0.7071 imu_link rslidar_head &

# 6. Start FAST-LIO
ros2 run fast_lio fastlio_mapping --ros-args --params-file /tmp/m1_airy96_rot.yaml &
```

### Verification

```bash
source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=66 ROS_LOCALHOST_ONLY=0

# Check node
ros2 node list | grep laser_mapping

# Check LiDAR data
ros2 topic hz /front_lidar          # expect 8–10 Hz
ros2 topic hz /front_lidar/imu      # expect ~100 Hz

# Check odometry
ros2 topic echo /Odometry --once    # frame: odom → imu_link
ros2 topic hz /Odometry             # expect ~10 Hz

# Check registered cloud
ros2 topic hz /cloud_registered_body  # expect ~10 Hz

# Check TF tree
timeout 5 ros2 run tf2_ros tf2_echo odom rslidar_head
```

## Configuration Deep-Dive

### IMU Rotation (`imu_rot.py`)

| Step | Transform | Purpose |
|------|-----------|---------|
| Input | `linear_acceleration` = (ax, ay, az) with Y=g | Raw Airy96 IMU |
| Rotate | R_x(90°) → (ax, -az, ay) | Gravity: Y→Z axis |
| Output | Gravity = (0, 0, ~9.81) | Standard ROS Z-up |

FAST-LIO automatically normalizes acceleration (g → m/s²) during initialization.
No manual scaling needed.

### FAST-LIO Config (`m1_airy96_rot.yaml`)

```yaml
common:
  lid_topic:  "/front_lidar"       # Raw point cloud from rslidar_sdk
  imu_topic:  "/livox/imu"         # Rotated IMU (Z-up gravity)
  time_sync_en: true                # LiDAR-IMU time sync
  time_offset_lidar_to_imu: 0.0
  scan_rate: 10

preprocess:
  lidar_type: 5                     # RoboSense Airy96
  scan_line: 96
  timestamp_unit: 0                 # seconds

mapping:
  acc_cov: 0.1
  gyr_cov: 0.1
  b_acc_cov: 0.0001
  b_gyr_cov: 0.0001
  extrinsic_est_en: false
  extrinsic_R: [0, 0, 1,           # R_y(90°): LiDAR → body
                0, 1, 0,
                -1, 0, 0]

frames:
  map_frame: "map"
  odom_frame: "odom"
  body_frame: "imu_link"

publish:
  map_en: true
  dense_publish_en: true
  scan_bodyframe_pub_en: true
```

### TF Tree

```
map
 └─ odom            ← FAST-LIO publishes /tf
     └─ imu_link    ← FAST-LIO child_frame_id in /Odometry
         ├─ body           ← static (-0.404, 0, 0.038)
         └─ rslidar_head   ← static (R_y(90°))
```

## Build from Source (on NX)

```bash
# Clone or copy fastlio_src/ into ~/m1_ws/src/fast_lio/

# Option A: CPU-only build
cd ~/m1_ws
colcon build --packages-select fast_lio

# Option B: CUDA build (recommended for Orin)
cd ~/m1_ws
colcon build --packages-select fast_lio --cmake-args -DFASTLIO_USE_CUDA=ON
```

**Note**: On Jetson Orin, set `-DCMAKE_CUDA_ARCHITECTURES="87"` for the Orin GPU (Ampere SM 8.7).

## Key Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| `acc_cov` | 0.1 | Acceleration covariance (lower = trust IMU more) |
| `gyr_cov` | 0.1 | Gyroscope covariance |
| `extrinsic_R` | R_y(90°) | Must not be R_x(90°) — it breaks point registration |
| `body_frame` | `imu_link` | On NX. Use `body` only for local (non-NX) runs |
| `time_sync_en` | `true` | Enables LiDAR-IMU time alignment |

### Don't Change

- `extrinsic_R`: Keep as R_y(90°). R_x(90°) causes "No Effective Points!" on every frame.
- `lidar_type`: Keep as 5 (RoboSense). Type 1 (Livox) causes crash.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ros2 topic list` shows topics but `hz` gives 0 | NX node uses localhost locator | Set `ZENOH_SESSION_CONFIG_URI=/tmp/zenoh_nx_client.json5` |
| `No Effective Points` every frame | Wrong `extrinsic_R` or TF flip | Verify `extrinsic_R: R_y(90°)` and TF chain |
| Odometry drifts linearly after rotation | IMU angular velocity scaled | Don't scale `angular_velocity` in imu_rot.py |
| Odometry drifts slowly (0.1–1 m/s) | FAST-LIO not yet converged | Let robot stand still for 10s after start |
| `/Laser_map` has publisher but no data | `publish.map_en` not set | Set `publish.map_en: true` in config |
| `zombie` processes or duplicate publishers | Old processes not killed | `sudo killall -9 imu_rot fastlio_mapping` before start |
| CRASH: "Livox LiDAR support is disabled" | Using Livox config (lidar_type=1) | Use `lidar_type: 5` for RoboSense Airy96 |

## Files

```
m1_fastlio/
├── fastlio_src/          # FAST-LIO GPU source (ROS2 Humble)
│   ├── src/              # laserMapping.cpp, preprocess.cpp, IMU_Processing.hpp
│   ├── include/          # IKFoM, ikd-Tree, GPU utils
│   ├── config/           # Stock sensor configs + M1 custom configs
│   ├── msg/              # Custom ROS2 message (Pose6D)
│   ├── CMakeLists.txt    # Build system (CUDA optional)
│   └── package.xml       # ROS2 package manifest
├── scripts/              # Deployment scripts & configs
│   ├── imu_rot.py          # IMU rotation: R_x(90°), Y→Z gravity
│   ├── start_fastlio_nx.sh # One-click NX deployment
│   ├── m1_airy96_rot.yaml  # ⭐ Working FAST-LIO config (use this)
│   ├── zenoh_nx_client.json5 # Zenoh client config for NX
│   └── m1_airy96_*.yaml   # Reference/alternate configs
├── docs/
│   └── fastlio_doc/      # Original FAST-LIO documentation
└── README.md             # This file
```

## Credits

- **FAST-LIO2**: Xu W, Zhang F. FAST-LIO2: Fast Direct LiDAR-inertial Odometry. TPAMI 2022.
- **GPU fork**: [Omer Mersin](https://github.com/omermersin/fast_lio_gpu)
- **M1 integration & deployment**: Custom configuration for Genisom (智身科技) M1 robot
- **RoboSense Airy96**: lidar_type=5 integration

---

**License**: GPL-2.0-or-later (inherited from fast_lio_gpu)
