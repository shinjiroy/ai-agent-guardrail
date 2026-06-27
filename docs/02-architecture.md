# 02. アーキテクチャ

## 全体構成

```
┌─────────────────────────────────────────────────────────────┐
│  エージェント（Claude Code / Cursor）                          │
│   ツール実行前に Hook を起動し、stdin で JSON を渡す            │
└───────────────┬─────────────────────────────────────────────┘
                │ エージェント固有の入力JSON
                ▼
┌─────────────────────────────────────────────────────────────┐
│  アダプタ層  adapters/<agent>/<event>.sh                       │
│   1. エージェント固有入力 → 標準判定リクエストへ正規化          │
│   2. core/guardrail.sh を呼び出す                              │
│   3. 標準判定結果 → エージェント固有出力へ変換                  │
└───────────────┬─────────────────────────────────────────────┘
                │ 標準判定リクエスト(JSON, stdin)
                ▼
┌─────────────────────────────────────────────────────────────┐
│  共通判定エンジン  core/guardrail.sh （エージェント非依存）     │
│   - rules/*.json を読み込む                                    │
│   - operation に応じて deny-files / deny-commands を評価        │
│   - 最初に該当した deny ルールで判定確定                        │
└───────────────┬─────────────────────────────────────────────┘
                │ 標準判定結果(JSON, stdout)
                ▼
        アダプタが各エージェント形式へ変換して返す
```

**設計意図**: 判定ロジックとルールを `core/` + `rules/` に集約することで、エージェントが増えても
「アダプタを足すだけ」で同一要件を満たせる。アダプタはフォーマット変換に徹し、判定を行わない。

## ディレクトリ構成

```
ai-agent-guardrail/
├── rules/
│   ├── deny-files.json          # 機密ファイルのルール
│   └── deny-commands.json       # 危険コマンドのルール
├── core/
│   ├── guardrail.sh             # エントリポイント（標準入出力）
│   └── lib/
│       ├── json.sh              # jq ラッパ
│       ├── match_file.sh        # glob パターンマッチ
│       ├── match_command.sh     # regex / builtin 評価
│       └── builtins.sh          # builtin 評価関数群（rm_wildcard_outside_home 等）
├── adapters/
│   ├── claude/
│   │   └── pretooluse.sh        # Claude Code PreToolUse 用
│   └── cursor/
│       ├── before-shell.sh      # Cursor beforeShellExecution 用
│       └── before-read-file.sh  # Cursor beforeReadFile 用
├── tests/
│   ├── core/                    # エンジン単体テスト（bats）
│   ├── adapters/                # アダプタ変換テスト（bats）
│   └── fixtures/                # 入力JSONサンプル
├── docker/
│   └── Dockerfile               # bash + jq + bats
└── docker-compose.yaml
```

## 標準判定リクエスト（内部共通フォーマット）

アダプタがエージェント固有入力から組み立て、`core/guardrail.sh` の stdin へ渡すJSON。

```json
{
  "agent": "claude | cursor",
  "operation": "read | write | exec",
  "path": "/abs/or/relative/path",   // operation が read/write のとき必須
  "command": "rm -rf foo/*",         // operation が exec のとき必須
  "cwd": "/current/working/dir",     // builtin 評価（rm 判定等）で使用
  "home": "/home/user"               // 省略時は実行環境の $HOME を使用
}
```

- `operation` は3種に正規化する。各エージェントのツール名/イベント名をこの3種へマッピングするのがアダプタの責務。
- `path` は可能な限り絶対パスへ正規化する（相対パスは `cwd` 基準で解決）。

## 標準判定結果（内部共通フォーマット）

`core/guardrail.sh` が stdout に返すJSON。

```json
{
  "decision": "allow | deny",
  "rule_id": "curl-pipe-shell",        // deny のとき該当ルールID、allow のとき null
  "message": "理由メッセージ（deny のときルールの message）"
}
```

終了コード:
- `0`: 正常に判定できた（`decision` は stdout を参照）
- `非0`: エンジン内部エラー（設定不備、jq 不在など）。アダプタはこれを検知し、後述の fail-safe ポリシーに従う。

## 判定アルゴリズム（core/guardrail.sh）

1. stdin から標準判定リクエストを読む。
2. `operation` が `read` または `write` の場合:
   - `rules/deny-files.json` の各ルールについて、
     - `operations` に当該 operation が含まれ、かつ
     - `patterns` のいずれかが `path` に glob マッチするなら → **deny**（最初の該当で確定）。
3. `operation` が `exec` の場合:
   - `rules/deny-commands.json` の各ルールについて、
     - `match.type == "regex"` なら `command` に対し正規表現マッチ
     - `match.type == "builtin"` なら `match.evaluator` の関数を `command`/`cwd`/`home` を引数に呼ぶ
     - いずれかが真なら → **deny**（最初の該当で確定）。
4. どのルールにも該当しなければ → **allow**。

> ルール評価順序は JSON の配列順。より限定的・危険なルールを先に置くと、deny 時のメッセージが適切になる。

## fail-safe ポリシー

判定エンジンやアダプタが異常終了した場合の振る舞いは、誤検知による作業停止と、危険操作の見逃しのトレードオフ。
本リポジトリでは **デフォルト fail-open（異常時は allow）** とし、各エージェント設定で fail-closed を選べるようにする。

| 方針 | 挙動 | 設定方法 |
| --- | --- | --- |
| fail-open（既定） | エンジン異常時は操作を通す | アダプタが非0終了を握りつぶし allow を返す |
| fail-closed | エンジン異常時は操作を止める | Claude: アダプタが deny を返す / Cursor: Hook 定義に `failClosed: true` |

> 機密性を最優先する組織では fail-closed を推奨。リポジトリの既定は開発体験を優先して fail-open とし、ドキュメントで明示する。

## 正規化マッピング（operation 対応表）

| operation | Claude Code（ツール名 → operation） | Cursor（イベント → operation） |
| --- | --- | --- |
| `exec` | `Bash` → exec | `beforeShellExecution` → exec |
| `read` | `Read` → read | `beforeReadFile` → read |
| `write` | `Write` / `Edit` / `MultiEdit` → write | （`beforeWriteFile` 相当が無い。制約は [05](05-agent-cursor.md) 参照） |

詳細な入出力フォーマットは [04-agent-claude-code.md](04-agent-claude-code.md) / [05-agent-cursor.md](05-agent-cursor.md) を参照。
