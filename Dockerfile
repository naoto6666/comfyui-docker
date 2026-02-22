# ============================================================
# MOV Workflow Tool - RunPod ComfyUI Docker Template
# ============================================================
# Architecture: "Symlink方式"
#   - ComfyUI本体 + venv + カスタムノード → コンテナディスク (/opt/comfyui)
#   - モデル・出力・設定 → ワークスペース (/workspace) にシンボリックリンク
#   - Terminate → 再デプロイしてもComfyUI自体の再インストール不要（爆速起動）
# ============================================================

FROM nvidia/cuda:12.1.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV COMFYUI_DIR=/opt/comfyui
ENV VENV_DIR=/opt/comfyui/venv
ENV PIP_NO_CACHE_DIR=1

# ============================================================
# System dependencies
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    wget \
    curl \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# ComfyUI本体
# ============================================================
RUN git clone https://github.com/comfyanonymous/ComfyUI.git $COMFYUI_DIR

# Python仮想環境
RUN python3 -m venv $VENV_DIR && \
    $VENV_DIR/bin/pip install --upgrade pip setuptools wheel

# PyTorch (CUDA 12.1)
RUN $VENV_DIR/bin/pip install \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu121

# ComfyUI依存パッケージ
RUN $VENV_DIR/bin/pip install -r $COMFYUI_DIR/requirements.txt

# ============================================================
# カスタムノード（Wan2.2動画生成 + アップスケール + ユーティリティ）
# ============================================================
WORKDIR $COMFYUI_DIR/custom_nodes

# --- Wan2.2 動画生成 ---
# WanVideoWrapper: Wan2.2のComfyUI統合ノード
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# VideoHelperSuite: 動画入出力・プレビュー
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git

# --- アップスケール ---
# Ultimate Upscale: タイル分割アップスケール
RUN git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git

# --- ユーティリティ ---
# KJ Nodes: 便利ユーティリティ群
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git

# ControlNet Aux: プリプロセッサ群
RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git

# ComfyUI Manager: ノード管理UI
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# Impact Pack: 検出・セグメント系
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git

# ============================================================
# カスタムノードの依存パッケージを一括インストール
# ============================================================
RUN for dir in */; do \
        if [ -f "${dir}requirements.txt" ]; then \
            echo "=== Installing deps for ${dir} ===" && \
            $VENV_DIR/bin/pip install -r "${dir}requirements.txt" || true; \
        fi; \
        if [ -f "${dir}install.py" ]; then \
            echo "=== Running install.py for ${dir} ===" && \
            cd "${dir}" && $VENV_DIR/bin/python install.py && cd ..; \
        fi; \
    done

# ============================================================
# Jupyter Notebook（オプション: 管理用）
# ============================================================
RUN $VENV_DIR/bin/pip install jupyterlab

# ============================================================
# 起動スクリプト
# ============================================================
WORKDIR /
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188 8888

CMD ["/start.sh"]
