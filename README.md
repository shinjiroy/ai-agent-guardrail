# ai-agent-guardrail

複数のAIコーディングエージェント（Claude Code / Cursor）に対して、共通のガードレールを提供するリポジトリ。

エージェントが「叩いてはならないコマンド」や「触れてはならないファイル」へアクセスしようとした際に、
各エージェントの Hooks 機能を通じてその操作をブロックする。

## 何を解決するか

- 機密ファイル（`.env`、秘密鍵、クラウド資格情報など）の読み書きを防ぐ
- `curl ... | bash` のようなリモートコード直接実行を防ぐ
- ユーザーディレクトリ以下以外での、ワイルドカード付き `rm` を防ぐ
- Docker/Podman の CLI 上でのボリュームマウント（`-v` / `--volume` / `--mount`）を防ぐ
- 上記をエージェント横断で **同一のルール定義** から実現する

## 設計の核

> **エージェント非依存の共通判定エンジン（Bash）＋ 各エージェント用の薄いアダプタ**
>
> 禁止ルールは `rules/*.json` に一元管理し、Claude Code でも Cursor でも同じルールが適用される。
> 新しい禁止対象を増やしたいときは、原則 JSON に1行追記するだけで全エージェントへ反映される。

```text
エージェントのHook入力(JSON)
        │
        ▼
  アダプタ層（エージェント固有）   adapters/claude/*, adapters/cursor/*
   ・入力を「標準判定リクエスト」へ正規化
        │
        ▼
  共通判定エンジン（非依存）       core/guardrail.sh
   ・rules/*.json を読み、allow/deny を判定
        │
        ▼
  アダプタ層
   ・「標準判定結果」を各エージェントの出力フォーマットへ変換
        │
        ▼
エージェントのHook出力(JSON / exit code)
```

## クイックスタート

### 1. Hook のインストール

```bash
# Claude Code（ユーザー全体）
./install.sh claude --scope user

# Cursor（プロジェクト限定）
./install.sh cursor --scope project

# 機密性を最優先する場合（Cursor の fail-closed）
./install.sh cursor --scope user --fail-closed
```

### 2. テスト実行（Docker）

```bash
# テスト一式
docker compose run --rm test

# 単一ファイル
docker compose run --rm test bats tests/core/guardrail.bats

# 対話シェル（デバッグ用）
docker compose run --rm shell
```

### 3. 手動でエンジンを試す

```bash
echo '{"operation":"read","path":"/home/user/.env","cwd":"/home/user"}' \
  | ./core/guardrail.sh
```

## ディレクトリ構成

```text
ai-agent-guardrail/
├── README.md
├── install.sh                 # Hook 登録補助
├── docker-compose.yaml          # ローカルテスト・確認用
├── docs/                      # 設計ドキュメント
├── rules/                     # 禁止ルール定義（JSON）
│   ├── deny-files.json
│   └── deny-commands.json
├── core/                      # 共通判定エンジン
│   ├── guardrail.sh
│   └── lib/
├── adapters/                  # エージェント用アダプタ
│   ├── claude/pretooluse.sh
│   └── cursor/
│       ├── before-shell.sh
│       ├── before-read-file.sh
│       └── after-file-edit.sh
├── tests/                     # bats テスト
└── docker/                    # テスト用 Docker イメージ
```

## 対応エージェント

| エージェント | Hook | アダプタ |
| --- | --- | --- |
| Claude Code | `PreToolUse` | `adapters/claude/pretooluse.sh` |
| Cursor | `beforeShellExecution` | `adapters/cursor/before-shell.sh` |
| Cursor | `beforeReadFile` | `adapters/cursor/before-read-file.sh` |
| Cursor | `afterFileEdit`（事後検知） | `adapters/cursor/after-file-edit.sh` |

Cursor ではファイル編集の事前ブロックができない制約がある。詳細は [docs/05-agent-cursor.md](docs/05-agent-cursor.md) を参照。

## ルールの追加

新しい禁止対象は `rules/deny-files.json` または `rules/deny-commands.json` に追記する。
正規表現で表現できない判定のみ `core/lib/builtins.sh` に評価関数を追加する。
手順とスキーマは [docs/03-rules-spec.md](docs/03-rules-spec.md) を参照。

## ドキュメント

| ドキュメント | 内容 |
| --- | --- |
| [docs/00-conventions.md](docs/00-conventions.md) | リポジトリ規約（正本） |
| [docs/01-overview.md](docs/01-overview.md) | 目的・スコープ・対応エージェント |
| [docs/02-architecture.md](docs/02-architecture.md) | アーキテクチャ・データフロー |
| [docs/03-rules-spec.md](docs/03-rules-spec.md) | ルール JSON 仕様 |
| [docs/04-agent-claude-code.md](docs/04-agent-claude-code.md) | Claude Code 連携 |
| [docs/05-agent-cursor.md](docs/05-agent-cursor.md) | Cursor 連携と制約 |
| [docs/06-implementation-guide.md](docs/06-implementation-guide.md) | 実装指示書 |
| [docs/07-testing.md](docs/07-testing.md) | テスト方針 |
| [docs/08-additional-guardrails.md](docs/08-additional-guardrails.md) | 追加ガードレール候補 |

## 環境変数

| 変数 | 用途 |
| --- | --- |
| `GUARDRAIL_HOME` | リポジトリの絶対パス（アダプタが core を解決する） |
| `GUARDRAIL_RULES_DIR` | ルール JSON のディレクトリ（テスト・カスタム配布用） |
| `GUARDRAIL_FAIL_CLOSED` | Cursor アダプタの fail-closed 有効化（`true`） |
