#!/bin/bash
# ============================================================
# MOV Workflow Tool - RunPod ComfyUI Startup Script v2.0
# ============================================================
# シンボリックリンク方式:
#   Dockerイメージ内の /opt/comfyui を利用しつつ、
#   /workspace に永続データ（モデル・出力・設定）を配置する
#
# v2.0 Changes:
#   - 自動パッチ適用
#   - LoRA自動ダウンロード (CivitAI API)
#   - Network Volume対応
# ============================================================

set -e

COMFYUI_DIR=/opt/comfyui
WORKSPACE=/workspace
MODELS_DIR=$WORKSPACE/models
OUTPUT_DIR=$WORKSPACE/output
USER_DIR=$WORKSPACE/user
BACKUP_DIR=$WORKSPACE/backup
CUSTOM_NODES_EXTRA=$WORKSPACE/custom_nodes_extra
LORA_DIR=$MODELS_DIR/loras

echo "============================================"
echo "  MOV Workflow Tool - ComfyUI v2.0"
echo "============================================"

# ============================================================
# 1. ワークスペースのディレクトリ構造を作成
# ============================================================
echo "[1/7] Creating workspace directories..."
mkdir -p $MODELS_DIR/{checkpoints,loras,vae,controlnet,upscale_models,clip,unet,diffusion_models}
mkdir -p $LORA_DIR/Nsfw
mkdir -p $OUTPUT_DIR
mkdir -p $USER_DIR/default
mkdir -p $BACKUP_DIR
mkdir -p $CUSTOM_NODES_EXTRA

# ============================================================
# 2. モデルディレクトリをシンボリックリンク
#    /opt/comfyui/models/xxx → /workspace/models/xxx
# ============================================================
echo "[2/7] Setting up model symlinks..."

for model_type in checkpoints loras vae controlnet upscale_models clip unet diffusion_models; do
    target_dir="$COMFYUI_DIR/models/$model_type"
    source_dir="$MODELS_DIR/$model_type"

    if [ -d "$target_dir" ] && [ ! -L "$target_dir" ]; then
        if [ "$(ls -A $target_dir 2>/dev/null)" ]; then
            cp -rn "$target_dir/"* "$source_dir/" 2>/dev/null || true
        fi
        rm -rf "$target_dir"
    fi

    ln -sfn "$source_dir" "$target_dir"
    echo "  ✓ $model_type → $source_dir"
done

# ============================================================
# 3. 出力ディレクトリをリンク
# ============================================================
echo "[3/7] Setting up output symlink..."
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
echo "[4/7] Restoring user settings..."

if [ -d "$USER_DIR/default" ] && [ "$(ls -A $USER_DIR/default 2>/dev/null)" ]; then
    mkdir -p "$COMFYUI_DIR/user/default"
    cp -r "$USER_DIR/default/"* "$COMFYUI_DIR/user/default/" 2>/dev/null || true
    echo "  ✓ User settings restored from workspace"
else
    echo "  - No saved settings found (first run)"
fi

if [ -f "$BACKUP_DIR/comfyui_settings.tar.gz" ]; then
    echo "  ✓ Restoring from backup archive..."
    tar xzf "$BACKUP_DIR/comfyui_settings.tar.gz" -C "$COMFYUI_DIR/user/" 2>/dev/null || true
fi

# ============================================================
# 5. 追加カスタムノード（ワークスペースに永続化したもの）
# ============================================================
echo "[5/7] Linking extra custom nodes..."
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
# 6. 自動パッチ適用
# ============================================================
echo "[6/7] Applying patches..."
if [ -f /patches.sh ]; then
    bash /patches.sh
fi

# ============================================================
# 7. LoRA自動ダウンロード (CivitAI API)
# ============================================================
echo "[7/7] Checking LoRA files..."

# CivitAI APIキーが設定されている場合のみ
CIVITAI_API_KEY="${CIVITAI_API_KEY:-}"
LORA_LIST="$WORKSPACE/lora_list.txt"

# Docker内のlora_list.txtをworkspaceに自動コピー（初回のみ）
if [ ! -f "$LORA_LIST" ] && [ -f /lora_list.txt ]; then
    cp /lora_list.txt "$LORA_LIST"
    echo "  ✓ lora_list.txt copied to workspace"
fi

# lora_list.txt のフォーマット (1行1LoRA):
#   filename|civitai_version_id
# 例:
#   Nsfw/general-nsfw-high.safetensors|2073605
#   Nsfw/general-nsfw-low.safetensors|2073606

if [ -n "$CIVITAI_API_KEY" ] && [ -f "$LORA_LIST" ]; then
    echo "  LoRA auto-download enabled (CivitAI API)"
    while IFS='|' read -r lora_file version_id; do
        # コメント行と空行をスキップ
        [[ "$lora_file" =~ ^#.*$ ]] && continue
        [ -z "$lora_file" ] && continue

        target_path="$LORA_DIR/$lora_file"
        if [ ! -f "$target_path" ]; then
            echo "  ↓ Downloading: $lora_file (version $version_id)..."
            mkdir -p "$(dirname "$target_path")"
            wget -q -O "$target_path" \
                "https://civitai.com/api/download/models/${version_id}?token=${CIVITAI_API_KEY}" \
                || echo "  ✗ Failed to download $lora_file"
        else
            echo "  ✓ Already exists: $lora_file"
        fi
    done < "$LORA_LIST"
else
    if [ -z "$CIVITAI_API_KEY" ]; then
        echo "  - CIVITAI_API_KEY not set, skipping LoRA download"
    fi
    if [ ! -f "$LORA_LIST" ]; then
        echo "  - No lora_list.txt found, skipping"
    fi
fi

# ============================================================
# 起動
# ============================================================
echo ""
echo "============================================"
echo "  ComfyUI  → http://0.0.0.0:8188"
echo "  Jupyter   → http://0.0.0.0:8888"
echo "============================================"
echo ""

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
