#!/usr/bin/env python3
"""IMU rotation only: /front_lidar/imu → /livox/imu, R_x(90°) to put gravity in Z."""

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy, DurabilityPolicy
from sensor_msgs.msg import Imu

class ImuRot(Node):
    def __init__(self):
        super().__init__('imu_rot')
        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT,
                         history=HistoryPolicy.KEEP_LAST, durability=DurabilityPolicy.VOLATILE)
        self._sub = self.create_subscription(Imu, '/front_lidar/imu', self._cb, qos)
        self._pub = self.create_publisher(Imu, '/livox/imu', qos)
        self.get_logger().info('IMU R_x(90°) rotation started (Y→Z up)')

    def _cb(self, msg):
        ax = msg.linear_acceleration.x
        ay = msg.linear_acceleration.y
        az = msg.linear_acceleration.z
        gx = msg.angular_velocity.x
        gy = msg.angular_velocity.y
        gz = msg.angular_velocity.z
        # R_x(90°): native (Y=up) → ROS std (Z=up)
        msg.linear_acceleration.x = ax
        msg.linear_acceleration.y = -az
        msg.linear_acceleration.z = ay
        msg.angular_velocity.x = gx
        msg.angular_velocity.y = -gz
        msg.angular_velocity.z = gy
        self._pub.publish(msg)

def main():
    rclpy.init()
    rclpy.spin(ImuRot())

if __name__ == '__main__':
    main()

