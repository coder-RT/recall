# Recall's robot skill on ROS 2 Jazzy with Nav2 and its loopback simulator (a simulated robot that moves exactly as
# commanded: classic software, no models). An in-progress example, not part of the submission or Recall's install
# (Recall itself runs without Docker). Build: docker build -t recall-fetch examples/ros2-robot
FROM ros:jazzy-ros-base

RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-jazzy-navigation2 ros-jazzy-nav2-bringup ros-jazzy-nav2-loopback-sim ros-jazzy-nav2-simple-commander \
      ros-jazzy-vision-msgs python3-pip python3-numpy python3-scipy python3-yaml python3-pytest \
    && rm -rf /var/lib/apt/lists/*

# the A2A client (ask Recall) and httpx; Rerun to show the map, the things and the robot's path
RUN pip3 install --break-system-packages --no-cache-dir "a2a-sdk[http-server]==1.3.0" "httpx>=0.28" "rerun-sdk==0.24.1"

WORKDIR /ws
COPY recall_fetch_interfaces src/recall_fetch_interfaces
COPY recall_fetch src/recall_fetch
RUN . /opt/ros/jazzy/setup.sh && colcon build --symlink-install

ENTRYPOINT ["/bin/bash", "-c", "source /opt/ros/jazzy/setup.bash && source /ws/install/setup.bash && exec \"$@\"", "--"]
CMD ["bash"]
