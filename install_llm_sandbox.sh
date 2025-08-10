#!/bin/bash

set -e

install_docker() {
    echo "Installing Docker..."
    sudo dnf update -y
    sudo dnf install -y docker
    echo "Docker installed successfully."
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "Docker started and enabled."
}

# install_uv() {
#     echo "Installing uv..."
#     curl -LsSf https://astral.sh/uv/install.sh | sh
#     echo "uv installed successfully."
# }

install_python3() {
    echo "Installing Python..."
    sudo dnf install -y python3
    sudo dnf install -y python3-pip
    echo "Python installed successfully."
    echo "Python version: $(python3 --version)"
}

install_llmsandbox() {
    echo "Installing llmsandbox..."
    pip3 install llm-sandbox
    pip3 install 'llm-sandbox[docker]'
    pip3 install fastmcp
    echo "llmsandbox installed successfully."
}

install_npm() {
    echo "Installing Node.js and npm..."
    sudo dnf install -y nodejs npm
    echo "Node.js and npm installation completed."
    echo "Node.js version: $(node --version)"
    echo "npm version: $(npm --version)"
}

pull_docker_images() {
    echo "Pulling required Docker images for llm-sandbox..."
    
    local images=(
        "ghcr.io/vndee/sandbox-python-311-bullseye"
        "ghcr.io/vndee/sandbox-node-22-bullseye"
        "ghcr.io/vndee/sandbox-java-11-bullseye"
        "ghcr.io/vndee/sandbox-cpp-11-bullseye"
        "ghcr.io/vndee/sandbox-go-123-bullseye"
        "ghcr.io/vndee/sandbox-ruby-302-bullseye"
    )
    
    for image in "${images[@]}"; do
        echo "Pulling $image..."
        if docker pull "$image"; then
            echo "Successfully pulled $image"
        else
            echo "Warning: Failed to pull $image"
        fi
    done
    
    echo "Docker images pull completed."
}

setup_systemd_service() {
    echo "Setting up systemd service for llmsandbox..."
    
    # Copy service file to systemd directory
    cp llmsandbox.service /etc/systemd/system/
    
    # Reload systemd configuration
    systemctl daemon-reload
    
    # Enable service to start on boot
    systemctl enable llmsandbox
    
    # Create log file with proper permissions
    touch /var/log/llm-sandbox.log
    chmod 644 /var/log/llm-sandbox.log
    
    # Start the service
    systemctl start llmsandbox
    
    # Check service status
    if systemctl is-active --quiet llmsandbox; then
        echo "llmsandbox service started successfully"
        echo "Service status:"
        systemctl status llmsandbox --no-pager
    else
        echo "Error: Failed to start llmsandbox service"
        echo "Check logs with: journalctl -u llmsandbox -f"
        exit 1
    fi
}

install_docker
install_python3
install_llmsandbox
install_npm
pull_docker_images
setup_systemd_service
