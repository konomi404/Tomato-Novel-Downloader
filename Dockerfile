# 使用 Ubuntu 22.04 LTS 作为基础镜像
FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    INSTALL_DIR=/app \
    ACCEL_METHOD=direct \
    PORT=7860 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# 安装系统依赖和 Python 环境
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    # Pillow 依赖
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    # lxml 依赖
    libxml2-dev \
    libxslt-dev \
    # Edge-TTS 可能需要的依赖
    ffmpeg \
    # 其他可能的系统依赖
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 创建应用目录
WORKDIR /app

# 复制 requirements.txt 到容器中
COPY requirements.txt .

# 安装 Python 依赖（使用国内镜像加速）
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt

# 复制安装脚本
COPY installer_silent.sh /tmp/installer_silent.sh

# 运行安装脚本
RUN chmod +x /tmp/installer_silent.sh && \
    /tmp/installer_silent.sh && \
    rm /tmp/installer_silent.sh

# 创建启动脚本
RUN cat > /app/start.sh << 'EOF'
#!/bin/bash
# 读取 Hugging Face Spaces 注入的 PORT 环境变量
PORT=${PORT:-7860}
echo "Starting Tomato Novel Downloader on port $PORT"

# 检查 Python 依赖是否安装成功
echo "Python packages:"
python3 -c "import ascii_magic, bs4, PIL, edge_tts; print('✓ Core packages imported successfully')"

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

# 创建非 root 用户（安全最佳实践）
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    chown -R appuser:appuser /app

# 切换到非 root 用户
USER appuser

# 暴露端口（注意：Hugging Face Spaces 使用 PORT 环境变量）
EXPOSE 7860

# 设置容器健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-7860}/health 2>/dev/null || exit 1

# 设置容器启动命令
CMD ["/app/start.sh"]
