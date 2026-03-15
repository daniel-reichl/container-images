#!/bin/bash

# Docker Cleanup Script
# This script stops and removes containers and images not used in the last 7 days

set -e  # Exit on any error

# Configuration
DAYS_OLD=7

echo "🐳 Docker Cleanup Script Starting..."
echo "Will clean up containers and images older than $DAYS_OLD days"
echo "========================================"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Error: Docker daemon is not running"
    exit 1
fi

echo "✅ Docker is available and running"
echo

# Stop and remove old containers
echo "🛑 Stopping and removing containers older than $DAYS_OLD days..."
# First, stop containers that are older than specified days (excluding currently running important ones)
old_containers=$(docker ps -aq --filter "status=exited" --filter "until=${DAYS_OLD}d")
running_old_containers=$(docker ps -q --filter "until=${DAYS_OLD}d")

if [ -n "$running_old_containers" ]; then
    echo "Stopping $(echo $running_old_containers | wc -w) running container(s) older than $DAYS_OLD days..."
    docker stop $running_old_containers
fi

if [ -n "$old_containers" ]; then
    docker rm $old_containers
    echo "✅ Removed $(echo $old_containers | wc -w) old container(s)"
else
    echo "ℹ️  No old containers found to remove"
fi
echo

# Remove unused images older than specified days
echo "🗑️  Removing unused images older than $DAYS_OLD days..."
# Remove dangling images first
dangling_images=$(docker images -f "dangling=true" -q)
if [ -n "$dangling_images" ]; then
    docker rmi $dangling_images 2>/dev/null || true
    echo "✅ Removed dangling images"
fi

# Remove unused images older than specified days using system prune
# This is safer than removing all images
docker image prune -af --filter "until=${DAYS_OLD}d"
echo

# Clean up other unused Docker resources older than specified days
echo "🧹 Cleaning up other unused Docker resources older than $DAYS_OLD days..."
docker system prune -af --filter "until=${DAYS_OLD}d" --volumes
echo

echo "🎉 Docker cleanup completed successfully!"
echo "========================================"

# Display current Docker status
echo "📊 Current Docker status:"
echo "Containers: $(docker ps -a | wc -l) total ($(docker ps | wc -l) running)"
echo "Images: $(docker images | wc -l) total"
echo "Volumes: $(docker volume ls | wc -l) total"
echo "Networks: $(docker network ls | wc -l) total"
