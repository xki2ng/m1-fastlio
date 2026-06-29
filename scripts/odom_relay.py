#!/usr/bin/env python3
"""Relay FAST-LIO /Odometry → /odom/localization_odom for robot_forward TfManager."""
import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry

class OdomRelay(Node):
    def __init__(self):
        super().__init__('odom_relay')
        self._sub = self.create_subscription(Odometry, '/Odometry', self._cb, 10)
        self._pub_loc = self.create_publisher(Odometry, '/odom/localization_odom', 10)
        self._pub_slam = self.create_publisher(Odometry, '/odom/slam_odom', 10)
        self.get_logger().info('Relaying /Odometry → /odom/localization_odom + /odom/slam_odom')

    def _cb(self, msg):
        self._pub_loc.publish(msg)
        self._pub_slam.publish(msg)

def main():
    rclpy.init()
    rclpy.spin(OdomRelay())

if __name__ == '__main__':
    main()
