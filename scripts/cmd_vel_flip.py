#!/usr/bin/env python3
"""Flip cmd_vel X sign: Nav2 cmd_vel → flipped /cmd_vel (for robot_forward)"""
import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist

class CmdVelFlip(Node):
    def __init__(self):
        super().__init__('cmd_vel_flip')
        # Nav2 publishes to /cmd_vel_nav, we flip and publish to /cmd_vel
        self._sub = self.create_subscription(Twist, '/cmd_vel_raw', self._cb, 10)
        self._pub = self.create_publisher(Twist, '/cmd_vel', 10)
        self.get_logger().info('Flipping /cmd_vel_nav → /cmd_vel (X sign reversed)')

    def _cb(self, msg):
        msg.linear.x = -msg.linear.x
        self._pub.publish(msg)

def main():
    rclpy.init()
    rclpy.spin(CmdVelFlip())

if __name__ == '__main__':
    main()
