#!/bin/bash
# ============================================================
# パッチスクリプト - ComfyUI既知バグの自動修正
# ============================================================
# v2.0で検出された問題を自動的にパッチ
# ============================================================

set -e

COMFYUI_DIR=/opt/comfyui

echo "  [patches] Applying ComfyUI patches..."

# ============================================================
# Patch 1: class_type KeyError (node_replace_manager.py)
# ComfyUI v0.14.1で group/reroute ノードにclass_typeが無いとクラッシュ
# ============================================================
MANAGER_FILE="$COMFYUI_DIR/app/node_replace_manager.py"
if [ -f "$MANAGER_FILE" ]; then
    if grep -q 'node_struct\["class_type"\]' "$MANAGER_FILE" 2>/dev/null; then
        sed -i 's/class_type = node_struct\["class_type"\]/class_type = node_struct.get("class_type")\n            if class_type is None:\n                continue/' "$MANAGER_FILE"
        echo "  ✓ Patched class_type KeyError in node_replace_manager.py"
    else
        echo "  - class_type patch not needed (already fixed or different version)"
    fi
fi

# ============================================================
# Patch 2: fp16_accumulation ValueError (WanVideoWrapper)
# PyTorch 2.5.x doesn't have allow_fp16_accumulation attr
# ============================================================
WAN_FILE="$COMFYUI_DIR/custom_nodes/ComfyUI-WanVideoWrapper/nodes_model_loading.py"
if [ -f "$WAN_FILE" ]; then
    if grep -q 'raise ValueError.*allow_fp16_accumulation' "$WAN_FILE" 2>/dev/null; then
        sed -i 's/raise ValueError("torch.backends.cuda.matmul.allow_fp16_accumulation is not available in this version of torch, requires torch 2.7.0.dev2025 02 26 nightly minimum currently")/pass  # skipped: fp16_accumulation not available (PyTorch < 2.7)/' "$WAN_FILE"
        # Clear pycache
        rm -rf "$COMFYUI_DIR/custom_nodes/ComfyUI-WanVideoWrapper/__pycache__"
        echo "  ✓ Patched fp16_accumulation ValueError in WanVideoWrapper"
    else
        echo "  - fp16_accumulation patch not needed (already fixed or different version)"
    fi
fi

echo "  [patches] Done."
