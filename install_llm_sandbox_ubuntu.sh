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
    
    # 卸载旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # 更新包索引
    apt-get update
    
    # 安装依赖
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # 添加Docker官方GPG密钥
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # 设置仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 更新包索引
    apt-get update
    
    # 安装Docker
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # 启动并启用Docker
    systemctl start docker
    systemctl enable docker
    
    # 添加当前用户到docker组
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
        echo "已将用户 $SUDO_USER 添加到docker组"
    fi
    
    echo "Docker安装完成"
}

# 安装Python3
install_python3() {
    echo "开始安装Python3..."
    
    if command_exists python3 && command_exists pip3; then
        echo "Python3和pip3已安装"
        echo "Python版本: $(python3 --version)"
        return 0
    fi
    
    apt-get update
    apt-get install -y python3 python3-pip python3-venv
    
    echo "Python3安装完成"
    echo "Python版本: $(python3 --version)"
    echo "pip版本: $(pip3 --version)"
}

# 安装llmsandbox
install_llmsandbox() {
    echo "开始安装llmsandbox..."
    
    # 升级pip
    pip3 install --upgrade pip --break-system-packages
    
    # 安装llm-sandbox和相关依赖
    pip3 install llm-sandbox --break-system-packages
    pip3 install 'llm-sandbox[docker]' --break-system-packages
    pip3 install fastmcp --break-system-packages
    
    echo "llmsandbox安装完成"
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
    
    # 使用NodeSource仓库安装最新LTS版本
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
    
    echo "Node.js和npm安装完成"
    echo "Node.js版本: $(node --version)"
    echo "npm版本: $(npm --version)"
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

# 设置systemd服务
setup_systemd_service() {
    echo "开始设置systemd服务..."
    
    # 复制服务文件
    if [[ -f "llmsandbox.service" ]]; then
        cp llmsandbox.service /etc/systemd/system/
    else
        echo "错误：找不到 llmsandbox.service 文件"
        exit 1
    fi
    
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
    echo "开始安装LLM Sandbox..."
    
    check_root
    check_ubuntu
    
    # 更新系统
    echo "更新系统包..."
    apt-get update
    apt-get upgrade -y
    
    # 安装组件
    install_docker
    install_python3
    install_npm
    install_llmsandbox
    pull_docker_images
    setup_systemd_service
    
    echo "LLM Sandbox安装完成！"
    echo "您可以使用以下命令管理服务："
    echo "  启动: sudo systemctl start llmsandbox"
    echo "  停止: sudo systemctl stop llmsandbox"
    echo "  重启: sudo systemctl restart llmsandbox"
    echo "  状态: sudo systemctl status llmsandbox"
    echo "  日志: sudo journalctl -u llmsandbox -f"
    
    if [[ -n "$SUDO_USER" ]]; then
        echo "注意：为了使docker组更改生效，您可能需要重新登录或运行："
        echo "  newgrp docker"
    fi
}

# 执行主函数
main
