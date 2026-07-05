# 06. 実装指示書（Cursor 向け）

このドキュメントは、本リポジトリのガードレールを実装するための作業指示。Cursor（または他のエージェント）が
これを読んで実装できる粒度で記述する。**各スクリプトには必ずテストコードをセットで作成すること**（[07-testing.md](07-testing.md)）。

## 前提・制約

- スクリプト言語は **Bash** を基本とする。JSON 解析には `jq` を使う。
- 実行環境・テスト環境は **Docker** で用意し、`docker-compose.yaml` でローカル確認できるようにする。
- ファイル作成時は末尾に改行を入れる。
- ルール（`rules/*.json`）と仕様（`docs/`）は既に定義済み。実装はそれに従う。判定ロジックを増やすときも
  まずルール仕様（[03](03-rules-spec.md)）に沿うこと。

## 実装タスク

### タスク1: 共通判定エンジン `core/`

[02-architecture.md](02-architecture.md) の「判定アルゴリズム」「標準判定リクエスト/結果」に従って実装する。

- `core/guardrail.sh`
  - stdin から標準判定リクエスト（JSON）を読む
  - `operation` が `read`/`write` → `rules/deny-files.json` を評価
  - `operation` が `exec` → `rules/deny-commands.json` を評価
  - 最初に該当した deny ルールで確定。なければ allow
  - stdout に標準判定結果（JSON）を出力。内部エラー時は非0終了
  - ルールファイルのパスは環境変数 `GUARDRAIL_RULES_DIR`（既定はリポジトリ内 `rules/`）で上書き可能にする（テスト用）
- `core/lib/json.sh` … `jq` ラッパ、入力バリデーション
- `core/lib/match_file.sh` … glob→regex 変換とパスマッチ（[03](03-rules-spec.md) の glob 仕様）
- `core/lib/match_command.sh` … regex 評価と builtin ディスパッチ
- `core/lib/builtins.sh` … builtin 評価関数。少なくとも `rm_wildcard_outside_home` を実装

**受け入れ条件**: `tests/core/` の全テストが Docker 上で green。

### タスク2: Claude Code アダプタ `adapters/claude/pretooluse.sh`

[04-agent-claude-code.md](04-agent-claude-code.md) の擬似コードに従う。

- `tool_name` を operation/path/command へ正規化
- `core/guardrail.sh` を呼び、結果を `permissionDecision` 形式へ変換
- 対象外ツール・allow 時は何も出力せず exit 0
- deny 時のみ `hookSpecificOutput.permissionDecision = "deny"` を出力
- エンジン異常時は fail-safe ポリシー（既定 fail-open）に従う

**受け入れ条件**: `tests/adapters/claude/` が green。

### タスク3: Cursor アダプタ `adapters/cursor/`

[05-agent-cursor.md](05-agent-cursor.md) に従う。

- `before-shell.sh` … `beforeShellExecution` 用（operation=exec）
- `before-read-file.sh` … `beforeReadFile` 用（operation=read）
- `after-file-edit.sh` … `afterFileEdit` 用（write の事後検知・警告）。事前ブロック不可の制約を埋める
- 結果を `{"permission": "deny|allow", ...}` 形式へ変換

**受け入れ条件**: `tests/adapters/cursor/` が green。

### タスク4: テスト一式 `tests/`

[07-testing.md](07-testing.md) に従い `bats` で実装する。最低限のケース:

- 機密ファイル read/write の deny（Claude/Cursor 両方）
- 無害ファイル read の allow
- `curl | bash` / `bash <(curl ...)` の deny
- `$HOME` 外でのワイルドカード `rm` の deny、`$HOME` 内での allow
- システムパスへの `rm -rf` の deny
- エンジン異常時の fail-safe 挙動
- アダプタの入出力フォーマット変換（fixtures を使った golden test）

### タスク5: 実行・テスト環境 `docker/`, `docker-compose.yaml`

- `docker/Dockerfile` … `bash` + `jq` + `bats`（必要なら `bats-support`/`bats-assert`）を含む
- `docker-compose.yaml` … `docker compose run --rm test` でテスト一式が走るサービスを定義
- README にローカル確認手順を追記

### タスク6: インストール補助 `install.sh`

- 引数でエージェント種別（`claude` / `cursor`）と対象スコープ（user/project）を受け取る
- リポジトリのリリース断面（`core/` `adapters/` `rules/`）をインストール先へコピーする
  （既定: `${XDG_DATA_HOME:-~/.local/share}/ai-agent-guardrail`。`--install-dir` で上書き可能）
- 対応する設定ファイル（`settings.json` / `hooks.json`）へ Hook 定義を **マージ**（既存設定を壊さない）。
  Hook のコマンドパスは **インストール先** のアダプタを指す（開発 clone を参照しない）
- 再インストールでインストール先のコピーを丸ごと入れ替える（更新フロー: clone で変更 → テスト → 再インストール）
- `install.sh` 自体にもテストを用意する

## 実装順序の推奨

1. タスク1（core）+ タスク4の core テスト … ここが全要件の心臓部
2. タスク2（Claude アダプタ）+ テスト
3. タスク3（Cursor アダプタ）+ テスト
4. タスク5（Docker 環境）
5. タスク6（install.sh）

## 完了の定義（Definition of Done）

- [x] `rules/*.json` の全ルールが core で評価され、期待通り allow/deny される
- [x] Claude Code / Cursor 双方で、初期要件3項目（機密ファイル・curl パイプ・rm）がブロックされる
- [x] 全テストが Docker 上で green（`docker compose run --rm test`）
- [x] 新ルール追加が「JSON 追記＋テスト追加」だけで完結する設計
- [x] README にセットアップ・ローカル確認手順が記載されている
