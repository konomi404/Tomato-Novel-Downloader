# 使用 Ubuntu 22.04 LTS 作为基础镜像
FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    INSTALL_DIR=/app \
    ACCEL_METHOD=direct \
    PORT=7860

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    jq \
    && rm -rf /var/lib/apt/lists/*

# 创建应用目录
WORKDIR /app

# 复制安装脚本
COPY installer_silent.sh /tmp/installer_silent.sh

# 运行安装脚本
RUN chmod +x /tmp/installer_silent.sh && \
    /tmp/installer_silent.sh && \
    rm /tmp/installer_silent.sh

# 创建启动脚本
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
# 读取 PORT 环境变量
PORT=${PORT:-7860}
echo "Starting Tomato Novel Downloader on port $PORT"

# 如果二进制文件存在，直接运行
if [ -f "/app/tomato-novel-downloader" ]; then
    /app/tomato-novel-downloader --port $PORT
elif [ -f "/app/run.sh" ]; then
    /app/run.sh --port $PORT
else
    # 查找最新的二进制文件
    LATEST_BINARY=$(ls -t /app/TomatoNovelDownloader-* 2>/dev/null | head -1)
    if [ -f "$LATEST_BINARY" ]; then
        chmod +x "$LATEST_BINARY"
        "$LATEST_BINARY" --port $PORT
    else
        echo "Error: No binary found in /app"
        exit 1
    fi
fi
EOF

# 设置执行权限
RUN chmod +x /app/start.sh

# 暴露端口
EXPOSE 7860

# 设置容器健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-7860}/health || exit 1

# 设置容器启动命令
CMD ["/app/start.sh"]
