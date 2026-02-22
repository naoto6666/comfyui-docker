#!/bin/bash
# ============================================================
# MOV Workflow Tool - RunPod ComfyUI Startup Script
# ============================================================
# シンボリックリンク方式:
#   Dockerイメージ内の /opt/comfyui を利用しつつ、
#   /workspace に永続データ（モデル・出力・設定）を配置する
# ============================================================

set -e

COMFYUI_DIR=/opt/comfyui
WORKSPACE=/workspace
MODELS_DIR=$WORKSPACE/models
OUTPUT_DIR=$WORKSPACE/output
USER_DIR=$WORKSPACE/user
BACKUP_DIR=$WORKSPACE/backup
CUSTOM_NODES_EXTRA=$WORKSPACE/custom_nodes_extra

echo "============================================"
echo "  MOV Workflow Tool - ComfyUI Startup"
echo "============================================"

# ============================================================
# 1. ワークスペースのディレクトリ構造を作成
# ============================================================
echo "[1/6] Creating workspace directories..."
mkdir -p $MODELS_DIR/{checkpoints,loras,vae,controlnet,upscale_models,clip,unet,diffusion_models}
mkdir -p $OUTPUT_DIR
mkdir -p $USER_DIR/default
mkdir -p $BACKUP_DIR
mkdir -p $CUSTOM_NODES_EXTRA

# ============================================================
# 2. モデルディレクトリをシンボリックリンク
#    /opt/comfyui/models/xxx → /workspace/models/xxx
# ============================================================
echo "[2/6] Setting up model symlinks..."

# メインモデルディレクトリ内の各サブフォルダをリンク
for model_type in checkpoints loras vae controlnet upscale_models clip unet diffusion_models; do
    target_dir="$COMFYUI_DIR/models/$model_type"
    source_dir="$MODELS_DIR/$model_type"

    # 既存のディレクトリの中身をワークスペースに移動（初回のみ）
    if [ -d "$target_dir" ] && [ ! -L "$target_dir" ]; then
        # ディレクトリ内のファイルをコピー（あれば）
        if [ "$(ls -A $target_dir 2>/dev/null)" ]; then
            cp -rn "$target_dir/"* "$source_dir/" 2>/dev/null || true
        fi
        rm -rf "$target_dir"
    fi

    # シンボリックリンク作成
    ln -sfn "$source_dir" "$target_dir"
    echo "  ✓ $model_type → $source_dir"
done

# ============================================================
# 3. 出力ディレクトリをリンク
# ============================================================
echo "[3/6] Setting up output symlink..."
if [ -d "$COMFYUI_DIR/output" ] && [ ! -L "$COMFYUI_DIR/output" ]; then
    if [ "$(ls -A $COMFYUI_DIR/output 2>/dev/null)" ]; then
        cp -rn "$COMFYUI_DIR/output/"* "$OUTPUT_DIR/" 2>/dev/null || true
    fi
    rm -rf "$COMFYUI_DIR/output"
fi
ln -sfn "$OUTPUT_DIR" "$COMFYUI_DIR/output"
echo "  ✓ output → $OUTPUT_DIR"

# ============================================================
# 4. ユーザー設定の復元（ワークフロー、サブグラフ等）
# ============================================================
echo "[4/6] Restoring user settings..."

# user/default ディレクトリが存在し中身があれば復元
if [ -d "$USER_DIR/default" ] && [ "$(ls -A $USER_DIR/default 2>/dev/null)" ]; then
    # ComfyUIのuserディレクトリに設定を復元
    mkdir -p "$COMFYUI_DIR/user/default"
    cp -r "$USER_DIR/default/"* "$COMFYUI_DIR/user/default/" 2>/dev/null || true
    echo "  ✓ User settings restored from workspace"
else
    echo "  - No saved settings found (first run)"
fi

# バックアップからの復元（tar.gz形式）
if [ -f "$BACKUP_DIR/comfyui_settings.tar.gz" ]; then
    echo "  ✓ Restoring from backup archive..."
    tar xzf "$BACKUP_DIR/comfyui_settings.tar.gz" -C "$COMFYUI_DIR/user/" 2>/dev/null || true
fi

# ============================================================
# 5. 追加カスタムノード（ワークスペースに永続化したもの）
# ============================================================
echo "[5/6] Linking extra custom nodes..."
if [ -d "$CUSTOM_NODES_EXTRA" ] && [ "$(ls -A $CUSTOM_NODES_EXTRA 2>/dev/null)" ]; then
    for node_dir in "$CUSTOM_NODES_EXTRA"/*/; do
        node_name=$(basename "$node_dir")
        target="$COMFYUI_DIR/custom_nodes/$node_name"
        if [ ! -e "$target" ]; then
            ln -sfn "$node_dir" "$target"
            echo "  ✓ Extra node: $node_name"
        fi
    done
else
    echo "  - No extra custom nodes"
fi

# ============================================================
# 6. ComfyUI + JupyterLab 起動
# ============================================================
echo "[6/6] Starting services..."
echo ""
echo "  ComfyUI  → http://0.0.0.0:8188"
echo "  Jupyter   → http://0.0.0.0:8888"
echo ""
echo "============================================"

# JupyterLabをバックグラウンドで起動
$COMFYUI_DIR/venv/bin/jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --allow-root \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --notebook-dir=$WORKSPACE \
    &

# ComfyUIをフォアグラウンドで起動
cd $COMFYUI_DIR
exec $COMFYUI_DIR/venv/bin/python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --preview-method auto
