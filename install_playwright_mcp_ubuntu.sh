#!/bin/bash

set -e

# 检查Docker是否安装
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 安装Docker
install_docker() {
    echo "开始安装Docker..."
    
    if command_exists docker; then
        echo "Docker已安装，版本: $(docker --version)"
        return 0
    fi
    
    # 检查snap是否可用
    if ! command_exists snap; then
        echo "错误：snap未安装，无法使用snap安装Docker"
        exit 1
    fi
    
    # 使用snap安装Docker
    echo "使用snap安装Docker..."
    snap install docker
    
    # 等待Docker服务启动
    echo "等待Docker服务启动..."
    sleep 5
    
    # 验证Docker是否正常运行
    if ! docker info >/dev/null 2>&1; then
        echo "警告：Docker服务可能未正常运行，尝试手动启动..."
        systemctl start snap.docker.dockerd
        systemctl enable snap.docker.dockerd
    fi
    
    # 添加当前用户到docker组（snap版本）
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
        echo "已将用户 $SUDO_USER 添加到docker组"
    fi
    
    echo "Docker安装完成（使用snap）"
}

# 拉取Playwright MCP镜像
pull_playwright_image() {
    echo "开始拉取Playwright MCP镜像..."
    docker pull mcr.microsoft.com/playwright/mcp
    echo "Playwright MCP镜像拉取完成"
}

# 启动Playwright MCP服务
start_playwright_service() {
    echo "正在启动Playwright MCP服务..."
    docker run -d --name playwright-mcp --rm --init -p8931:8931 --log-opt max-size=10m --log-opt max-file=3 mcr.microsoft.com/playwright/mcp --port 8931
    echo "服务已启动，监听端口8931"
}

# 主安装流程
main() {
    echo "开始安装Playwright MCP..."
    
    install_docker
    pull_playwright_image
    start_playwright_service
    
    echo ""
    echo "Playwright MCP安装完成并已启动服务！"
    echo "服务运行命令："
    echo "  sudo docker run -d --restart always --name playwright-mcp --init -p8931:8931 mcr.microsoft.com/playwright/mcp --port 8931"
    echo ""
    echo "注意：如果当前用户不在docker组，可能需要重新登录或运行："
    echo "  newgrp docker"
}

# 执行主函数
main
