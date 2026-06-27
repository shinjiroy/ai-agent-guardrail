# ai-agent-guardrail

複数のAIコーディングエージェント（Claude Code / Cursor）に対して、共通のガードレールを提供するリポジトリ。

エージェントが「叩いてはならないコマンド」や「触れてはならないファイル」へアクセスしようとした際に、
各エージェントの Hooks 機能を通じてその操作をブロックする。

## 何を解決するか

- 機密ファイル（`.env`、秘密鍵、クラウド資格情報など）の読み書きを防ぐ
- `curl ... | bash` のようなリモートコード直接実行を防ぐ
- ユーザーディレクトリ以下以外での、ワイルドカード付き `rm` を防ぐ
- 上記をエージェント横断で **同一のルール定義** から実現する

## 設計の核

> **エージェント非依存の共通判定エンジン（Bash）＋ 各エージェント用の薄いアダプタ**
>
> 禁止ルールは `rules/*.json` に一元管理し、Claude Code でも Cursor でも同じルールが適用される。
> 新しい禁止対象を増やしたいときは、原則 JSON に1行追記するだけで全エージェントへ反映される。

```
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

## ドキュメント

このリポジトリの現状の成果物は **設計ドキュメント一式** である。実装は本ドキュメントに従って Cursor が行う。

| ドキュメント | 内容 |
| --- | --- |
| [docs/01-overview.md](docs/01-overview.md) | 目的・スコープ・対応エージェント・用語 |
| [docs/02-architecture.md](docs/02-architecture.md) | 共通エンジン＋アダプタ設計、ディレクトリ構成、データフロー |
| [docs/03-rules-spec.md](docs/03-rules-spec.md) | ルールJSONの仕様・追加方法 |
| [docs/04-agent-claude-code.md](docs/04-agent-claude-code.md) | Claude Code 連携の詳細 |
| [docs/05-agent-cursor.md](docs/05-agent-cursor.md) | Cursor 連携の詳細と制約 |
| [docs/06-implementation-guide.md](docs/06-implementation-guide.md) | Cursor 向け実装指示書（タスク分解） |
| [docs/07-testing.md](docs/07-testing.md) | テスト方針（必須） |
| [docs/08-additional-guardrails.md](docs/08-additional-guardrails.md) | 追加で検討すべきガードレール |

## ディレクトリ構成（実装後の目標形）

```
ai-agent-guardrail/
├── README.md
├── docs/                      # 設計ドキュメント（本リポジトリの現成果物）
├── rules/                     # 禁止ルール定義（JSONで一元管理）
│   ├── deny-files.json
│   └── deny-commands.json
├── core/                      # エージェント非依存の共通判定エンジン（Bash）
│   ├── guardrail.sh
│   └── lib/
├── adapters/                  # 各エージェント用アダプタ
│   ├── claude/
│   └── cursor/
├── tests/                     # テストコード（bats）
├── docker/                    # 実行・テスト環境（Docker）
├── docker-compose.yaml        # ローカル動作確認用
└── install.sh                 # 各エージェントへのHook登録補助
```

> 注: `core/`, `adapters/`, `tests/`, `install.sh` は未実装。`rules/` と `docs/` が現時点の成果物。
