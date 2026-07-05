# ai-agent-guardrail

複数のAIコーディングエージェント（Claude Code / Cursor）に対して、共通のガードレールを提供するリポジトリ。

エージェントが「叩いてはならないコマンド」や「触れてはならないファイル」へアクセスしようとした際に、
各エージェントの Hooks 機能を通じてその操作をブロックする。

## 何を解決するか

- 機密ファイル（`.env`、秘密鍵、クラウド資格情報、Terraform state、シェル履歴など）の読み書きを防ぐ。ネイティブの Read/Write だけでなく、`cat`/`grep`/インタプリタ経由の読み取りや、リダイレクト・`tee`・`cp`/`mv` 経由の書き込みも捕捉する
- `curl ... | bash` のようなリモートコード直接実行を防ぐ。中間パイプ（`| base64 -d | sh`）、インタプリタ（`| python3`）、コマンド置換（`sh -c "$(curl ...)"`）、プロセス置換（`source <(curl ...)`）も対象
- 破壊的操作を防ぐ: ユーザーディレクトリ以下以外でのワイルドカード付き `rm`、`git reset --hard` / `git clean -f`、保護ブランチ（main/master）への force push、ブロックデバイスへの `dd`、`mkfs`/`fdisk`、`chmod -R 777`
- ガードレール自身（インストール先の全ファイル）およびフック設定ファイル（`.claude/settings.json` 等）の改変を防ぐ
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

### 1. インストール

`install.sh` はリポジトリのリリース断面（`core/` `adapters/` `rules/`）をインストール先
（既定: `${XDG_DATA_HOME:-~/.local/share}/ai-agent-guardrail`）へコピーし、
フックが **インストール先** を参照するように登録する。

```bash
# Claude Code（ユーザー全体）
./install.sh claude --scope user

# Cursor（プロジェクト限定）
./install.sh cursor --scope project

# 機密性を最優先する場合（Cursor の fail-closed）
./install.sh cursor --scope user --fail-closed

# インストール先を指定する場合
./install.sh claude --scope user --install-dir /opt/ai-agent-guardrail
```

clone（開発用）とインストール先（実行用）を分離することで、ガードレールの自己保護ルール
（`guardrail-self-protection`）は **実行中のインストール先にのみ** 効き、clone は通常のリポジトリとして
エージェントでも編集できる。ルールやコードを更新したら、clone で変更・テストした後に `install.sh` を
再実行してインストール先へ反映する。

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
├── install.sh                 # インストール先へのコピーと Hook 登録
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

Cursor は Claude Code 互換の `preToolUse` フック（`~/.claude/settings.json` の PreToolUse 登録）も呼び出すため、
互換フックが有効な環境ではファイル編集の事前ブロックも効く。独自フック（`hooks.json`）のみの環境では
編集は afterFileEdit の事後検知となる。詳細は [docs/05-agent-cursor.md](docs/05-agent-cursor.md) を参照。

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
| `GUARDRAIL_HOME` | ガードレール設置先の絶対パス（アダプタが core を解決する。既定はアダプタ自身の位置から導出） |
| `GUARDRAIL_INSTALL_DIR` | 自己保護ルールが守る設置先パス（既定は実行中の `core/` の親。`install.sh` の既定インストール先の上書きにも使える） |
| `GUARDRAIL_RULES_DIR` | ルール JSON のディレクトリ（テスト・カスタム配布用） |
| `GUARDRAIL_FAIL_CLOSED` | アダプタ（Claude Code / Cursor）の fail-closed 有効化（`true`）。エンジン異常時に allow せず deny する |
