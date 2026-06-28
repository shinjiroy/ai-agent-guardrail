# セキュリティポリシー

## 報告方法

ガードレールの回避、誤検知・見逃し、ルール定義の不備など、セキュリティ上の問題を見つけた場合は
[GitHub Issues](https://github.com/shinjiroy/ai-agent-guardrail/issues) から報告してください。

公開前に詳細を共有したい場合は、Issue 作成時に「非公開で連絡希望」と記載してください。
可能な範囲で対応方法を相談します。

## 対象

- `core/` の判定ロジック
- `rules/*.json` のルール定義
- `adapters/` の Hook 連携
- `install.sh` による Hook 登録

## 対象外

- 各 AI エージェント本体（Claude Code / Cursor）の脆弱性
- 本リポジトリのガードレールを迂回しない、エージェント側の既知の制約（例: Cursor でファイル編集の事前ブロック不可）

## 対応方針

報告を確認後、影響範囲に応じて修正を行い、main ブランチへ反映します。
修正内容は可能な限り `tests/behavior/cases.jsonl` または関連テストで再発防止を確認します。
