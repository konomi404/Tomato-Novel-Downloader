# 使用官方 Ubuntu 作为基础镜像
FROM ubuntu:latest

# 更新并安装必要的依赖
RUN apt-get update && apt-get install -y \
    wget \
    bash \
    && rm -rf /var/lib/apt/lists/*

# 下载并解压指定的二进制文件
RUN wget -q https://github.com/zhongbai2333/Tomato-Novel-Downloader/releases/download/v1.8.5/TomatoNovelDownloader-Linux_amd64-v1.8.5 -O /usr/local/bin/TomatoNovelDownloader \
    && chmod +x /usr/local/bin/TomatoNovelDownloader

# 设置容器启动时默认执行的命令
ENTRYPOINT ["/bin/bash"]
