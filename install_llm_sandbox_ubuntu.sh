#!/bin/bash

set -e

# 检查是否为Ubuntu系统
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        echo "此脚本仅支持Ubuntu系统"
        exit 1
    fi
    
    . /etc/os-release
    echo "检测到Ubuntu版本: $VERSION"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "此脚本需要以root权限运行"
        echo "请使用: sudo ./install_llm_sandbox_ubuntu.sh"
        exit 1
    fi
}

# 检查命令是否存在
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

# 安装uv包管理器
install_uv() {
    echo "开始安装uv包管理器..."
    
    if command_exists uv; then
        echo "uv已安装，版本: $(uv --version)"
        return 0
    fi
    
    # 安装uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # 确保uv在PATH中
    export PATH="/root/.local/bin:$PATH"
    
    echo "uv安装完成"
}

# 安装Node.js和npm
install_npm() {
    echo "开始安装Node.js和npm..."
    
    if command_exists node && command_exists npm; then
        echo "Node.js和npm已安装"
        echo "Node.js版本: $(node --version)"
        echo "npm版本: $(npm --version)"
        return 0
    fi
    
    # 检查snap是否可用
    if ! command_exists snap; then
        echo "错误：snap未安装，无法使用snap安装Node.js"
        exit 1
    fi
    
    # 使用snap安装Node.js（包含npm）
    echo "使用snap安装Node.js和npm..."
    snap install node --classic
    
    # 验证安装
    if command_exists node && command_exists npm; then
        echo "Node.js和npm安装完成（使用snap）"
        echo "Node.js版本: $(node --version)"
        echo "npm版本: $(npm --version)"
    else
        echo "错误：Node.js和npm安装失败"
        exit 1
    fi
}

install_supergateway() {
    echo "开始安装supergateway..."
    
    if command_exists supergateway; then
        echo "supergateway已安装"
        return 0
    fi
    npm install -g supergateway
    
    echo "supergateway安装完成"
}

# 使用uv安装llmsandbox
install_llmsandbox_with_uv() {
    echo "开始安装llmsandbox（使用uv）..."
    
    # 确保uv在PATH中
    export PATH="/root/.local/bin:$PATH"
    
    # 创建项目目录
    mkdir -p /opt/llm-sandbox
    cd /opt/llm-sandbox
    
    # 使用uv创建虚拟环境
    uv venv
    
    # 定义腾讯pip源
    PIP_INDEX_URL="https://mirrors.cloud.tencent.com/pypi/simple/"
    
    # 安装llm-sandbox和相关依赖
    uv pip install ./llm_sandbox-0.3.13-py3-none-any.whl
    uv pip install --index-url "$PIP_INDEX_URL" 'llm-sandbox[docker]'
    uv pip install --index-url "$PIP_INDEX_URL" fastmcp
    
    echo "llmsandbox安装完成（使用uv虚拟环境）"
}

# 拉取Docker镜像
pull_docker_images() {
    echo "开始拉取Docker镜像..."
    
    local images=(
        "ghcr.io/vndee/sandbox-python-311-bullseye"
        "ghcr.io/vndee/sandbox-node-22-bullseye"
        "ghcr.io/vndee/sandbox-java-11-bullseye"
        "ghcr.io/vndee/sandbox-cpp-11-bullseye"
        "ghcr.io/vndee/sandbox-go-123-bullseye"
        "ghcr.io/vndee/sandbox-ruby-302-bullseye"
    )
    
    for image in "${images[@]}"; do
        echo "正在拉取 $image..."
        if docker pull "$image"; then
            echo "成功拉取 $image"
        else
            echo "警告：拉取 $image 失败"
        fi
    done
    
    echo "Docker镜像拉取完成"
}

# 创建uv版本的systemd服务
create_uv_systemd_service() {
    echo "创建uv版本的systemd服务..."
    
    # 创建新的服务文件
    cat > /etc/systemd/system/llmsandbox.service << 'EOF'
[Unit]
Description=LLM Sandbox MCP Server (uv)
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llm-sandbox
ExecStart=supergateway --stdio "/opt/llm-sandbox/.venv/bin/python -m llm_sandbox.mcp_server.server"
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StandardOutput=append:/var/log/llm-sandbox.log
StandardError=append:/var/log/llm-sandbox.log

[Install]
WantedBy=multi-user.target
EOF
    
    echo "uv版本systemd服务创建完成"
}

# 创建logrotate配置文件
create_logrotate_config() {
    echo "创建logrotate配置文件..."
    
    cat > /etc/logrotate.d/llm-sandbox << 'EOF'
/var/log/llm-sandbox.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    
    echo "logrotate配置文件创建完成"
}

# 设置systemd服务
setup_systemd_service() {
    echo "开始设置systemd服务..."
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable llmsandbox
    
    # 创建日志文件
    touch /var/log/llm-sandbox.log
    chmod 644 /var/log/llm-sandbox.log
    
    # 启动服务
    systemctl start llmsandbox
    
    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet llmsandbox; then
        echo "llmsandbox服务启动成功"
        echo "服务状态:"
        systemctl status llmsandbox --no-pager
    else
        echo "错误：llmsandbox服务启动失败"
        echo "查看日志: journalctl -u llmsandbox -f"
        exit 1
    fi
}

# 主安装流程
main() {
    echo "开始安装LLM Sandbox（使用uv）..."
    
    check_root
    check_ubuntu
    
    # 更新系统
    echo "更新系统包..."
    apt-get update
    apt-get upgrade -y
    
    # 安装组件
    install_docker
    install_uv
    install_npm
    install_supergateway
    install_llmsandbox_with_uv
    pull_docker_images
    create_uv_systemd_service
    create_logrotate_config
    setup_systemd_service
    
    echo "LLM Sandbox安装完成（使用uv虚拟环境）！"
    echo "安装路径: /opt/llm-sandbox"
    echo "虚拟环境: /opt/llm-sandbox/.venv"
    echo ""
    echo "您可以使用以下命令管理服务："
    echo "  启动: sudo systemctl start llmsandbox"
    echo "  停止: sudo systemctl stop llmsandbox"
    echo "  重启: sudo systemctl restart llmsandbox"
    echo "  状态: sudo systemctl status llmsandbox"
    echo "  日志: sudo journalctl -u llmsandbox -f"
    echo ""
    echo "手动激活虚拟环境："
    echo "  source /opt/llm-sandbox/.venv/bin/activate"
    
    if [[ -n "$SUDO_USER" ]]; then
        echo "注意：为了使docker组更改生效，您可能需要重新登录或运行："
        echo "  newgrp docker"
    fi
}

# 执行主函数
main
