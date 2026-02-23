# ============================================================
# MOV Workflow Tool - RunPod ComfyUI Docker Template v2.0
# ============================================================
# Architecture: "Symlink方式"
#   - ComfyUI本体 + venv + カスタムノード → コンテナディスク (/opt/comfyui)
#   - モデル・出力・設定 → ワークスペース (/workspace) にシンボリックリンク
#   - Terminate → 再デプロイしてもComfyUI自体の再インストール不要（爆速起動）
#
# v2.0 Changes:
#   - 旧ワークフロー(00-I2v_ImageToVideo_FINAL)に必要な全カスタムノード追加
#   - fp16_accumulation / class_type バグの自動パッチ
#   - LoRA自動ダウンロード対応
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
# カスタムノード — 動画生成コア
# ============================================================
WORKDIR $COMFYUI_DIR/custom_nodes

# WanVideoWrapper: Wan2.2のComfyUI統合ノード
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# VideoHelperSuite: 動画入出力・プレビュー
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git

# ============================================================
# カスタムノード — アップスケール・画像処理
# ============================================================

# Ultimate Upscale: タイル分割アップスケール
RUN git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git

# ============================================================
# カスタムノード — ユーティリティ (基本)
# ============================================================

# KJ Nodes: 便利ユーティリティ群
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git

# ControlNet Aux: プリプロセッサ群
RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git

# ComfyUI Manager: ノード管理UI
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# Impact Pack: 検出・セグメント系 (SAM2, UltralyticsDetectorProvider含む)
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git

# ============================================================
# カスタムノード — VACE (キャラクター一貫性 + SVI無限動画)
# ============================================================

# WanVaceAdvanced: VACE制御ノード
RUN git clone https://github.com/drozbay/ComfyUI-WanVaceAdvanced.git

# Wan-VACE-Prep: クリップ間のスムーズな接続用ノード
RUN git clone https://github.com/stuttlepress/ComfyUI-Wan-VACE-Prep.git

# ============================================================
# カスタムノード — 旧ワークフロー(00-I2v)で必要なノード
# ============================================================

# rgthree: Mute/Bypass Repeater, Fast Groups Bypasser, Any Switch, Label, etc.
RUN git clone https://github.com/rgthree/rgthree-comfy.git

# ComfyUI_essentials: 基本ユーティリティ
RUN git clone https://github.com/cubiq/ComfyUI_essentials.git

# tinyterraNodes: 追加ユーティリティ
RUN git clone https://github.com/TinyTerra/ComfyUI_tinyterraNodes.git

# KayTool: データ表示ノード
RUN git clone https://github.com/KayJayCee/ComfyUI-KayTool.git

# ComfyLiterals: リテラル値ノード
RUN git clone https://github.com/M1kep/ComfyLiterals.git

# ComfyUI Model Downloader: モデル自動ダウンロード
RUN git clone https://github.com/ciri/comfyui-model-downloader.git

# OllamaGemini: LLMプロンプト生成 (オプション)
RUN git clone https://github.com/fairy-root/ComfyUI-OllamaGemini.git

# pysssss Custom Scripts: StringFunction等
RUN git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

# RIFE VFI: フレーム補間
RUN git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git

# Florence2: 画像解析・自動プロンプト
RUN git clone https://github.com/kijai/ComfyUI-Florence2.git

# CyberEve: バッチイメージループ (Refiner用)
RUN git clone https://github.com/CyberEve/ComfyUI-CyberEve-Extensions.git || true

# mxSlider: スライダーウィジェット
RUN git clone https://github.com/mxmurw/ComfyUI-mxSlider.git || true

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
# Jupyter Notebook（管理用）
# ============================================================
RUN $VENV_DIR/bin/pip install jupyterlab

# ============================================================
# 起動スクリプト + パッチスクリプト
# ============================================================
WORKDIR /
COPY start.sh /start.sh
COPY patches.sh /patches.sh
COPY lora_list.txt /lora_list.txt
RUN chmod +x /start.sh /patches.sh

EXPOSE 8188 8888

CMD ["/start.sh"]
