# RunPod ComfyUI テンプレート — ビルド & デプロイ手順

## 概要

ハカセの有料テンプレートと同等の機能を自前で実現するDockerイメージ。

### 含まれるもの

| カテゴリ | ノード |
|---|---|
| 動画生成 | ComfyUI-WanVideoWrapper (Wan2.2) |
| 動画I/O | ComfyUI-VideoHelperSuite |
| アップスケール | ComfyUI_UltimateSDUpscale |
| ユーティリティ | ComfyUI-KJNodes |
| ControlNet | comfyui_controlnet_aux |
| 管理 | ComfyUI-Manager |
| 検出 | ComfyUI-Impact-Pack |

### アーキテクチャ（シンボリックリンク方式）

```
Docker Container (一時ディスク)           Workspace (永続ディスク)
┌──────────────────────────┐           ┌──────────────────────────┐
│ /opt/comfyui/            │           │ /workspace/              │
│   ├── venv/              │           │   ├── models/            │
│   ├── custom_nodes/      │           │   │   ├── checkpoints/   │
│   ├── models/ ────symlink──────────→ │   │   ├── loras/         │
│   ├── output/ ────symlink──────────→ │   │   └── ...            │
│   └── main.py            │           │   ├── output/            │
└──────────────────────────┘           │   ├── user/default/      │
                                       │   ├── backup/            │
Terminate → 消える                     │   └── custom_nodes_extra/│
(次回デプロイで自動再構築)               └──────────────────────────┘
                                       Stop → 残る
                                       Terminate → 消える（要バックアップ）
```

---

## ビルド手順

### 1. Docker Hub アカウント準備

```bash
# Docker Hub にログイン（無料アカウントでOK）
docker login
```

### 2. イメージをビルド

```bash
cd /Users/naoto/Desktop/My-Tool/mov-workflow-tool/docker

# ビルド（15〜30分かかる）
docker build -t naotodev66/comfyui-wan22:latest .

# ※ Macの場合、linux/amd64 向けにビルドする必要がある
docker buildx build --platform linux/amd64 -t naotodev66/comfyui-wan22:latest .
```

### 3. Docker Hub にプッシュ

```bash
docker push naotodev66/comfyui-wan22:latest
```

### 4. RunPod でテンプレート作成

1. [RunPod Console](https://console.runpod.io) にログイン
2. **Templates** → **New Template** をクリック
3. 以下を入力:

| 項目 | 値 |
|---|---|
| Template Name | `ComfyUI Wan2.2 (My Template)` |
| Container Image | `naotodev66/comfyui-wan22:latest` |
| Container Disk | `30 GB`（ComfyUI + ノード + venv） |
| Volume Disk | `50 GB`（モデル・出力用、必要に応じて拡大） |
| Expose HTTP Ports | `8188, 8888` |
| Docker Command | （空欄 — Dockerfile の CMD を使用） |

4. **Save Template**

### 5. Pod をデプロイ

1. **GPU Cloud** → **Deploy**
2. 作成したテンプレートを選択
3. GPU を選択（推奨: A40 $0.39/hr、L40S $0.74/hr）
4. **Deploy** をクリック
5. 約5分で起動完了

### 6. 接続

- **ComfyUI**: Connect → Port 8188
- **JupyterLab**: Connect → Port 8888

---

## 運用フロー

### 日常の使い方

```
1. RunPod → テンプレートからデプロイ（5分で起動）
2. ComfyUI で作業（動画生成、アップスケール等）
3. 終わったら:
   a. MOV Toolからバックアップ実行（設定 + 成果物をダウンロード）
   b. RunPod → Stop → Terminate（課金ストップ）
```

### モデルのダウンロード

初回デプロイ時は `/workspace/models/` が空なので、
ComfyUI Manager やワークフロー内のダウンロードノードでモデルを取得。

RunPod のデータセンターは **2〜10 Gbps** なので、
数GBのモデルも数十秒でダウンロード完了。

### バックアップ対象

Terminate 前に必ず保存するもの:
- `/workspace/user/default/` — ワークフロー、設定
- `/workspace/output/` — 生成結果（必要なもののみ）

モデルファイルはサイズが大きいのでバックアップ不要。
再デプロイ時にワークフローから再ダウンロードすればOK。

---

## カスタムノードの追加

### 方法1: Dockerイメージに追加（推奨）

`Dockerfile` にノードの `git clone` を追記して再ビルド。
全環境で常に使えるようになる。

### 方法2: ワークスペースに追加（一時的）

```bash
cd /workspace/custom_nodes_extra
git clone https://github.com/xxx/ComfyUI-NewNode.git
# → start.sh が自動でシンボリックリンクを張る
```

---

## 自動停止タイマー

Web Terminal で以下を実行（2時間後に自動Stop）:

```bash
sleep 7200 && curl -X POST \
  "https://api.runpod.io/graphql?api_key=YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { podStop(input: { podId: \"YOUR_POD_ID\" }) { id } }"}'
```

※ MOV Tool の Pod管理UIからも自動停止を設定可能（将来実装予定）

---

## トラブルシューティング

### ComfyUI が起動しない
```bash
# Web Terminal から手動起動してエラーを確認
cd /opt/comfyui
./venv/bin/python main.py --listen 0.0.0.0 --port 8188
```

### カスタムノードのエラー
```bash
# 依存パッケージの手動インストール
cd /opt/comfyui/custom_nodes/問題のノード
/opt/comfyui/venv/bin/pip install -r requirements.txt
```

### VRAM不足
- A40 (48GB VRAM) なら通常十分
- Wan2.2 の高解像度生成時は VRAM 使用量に注意
- `--lowvram` フラグを追加して起動

---

## コスト目安

| GPU | 時給 | 月30時間利用 | 月60時間利用 |
|---|---|---|---|
| A40 (48GB) | $0.39 | $11.70 (≈¥1,755) | $23.40 (≈¥3,510) |
| A40 Spot | $0.20 | $6.00 (≈¥900) | $12.00 (≈¥1,800) |
| L40S (48GB) | $0.74 | $22.20 (≈¥3,330) | $44.40 (≈¥6,660) |

※ Terminate運用ならストレージ料金ゼロ
