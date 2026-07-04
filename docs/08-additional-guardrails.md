# 08. 追加で検討すべきガードレール

実装済みのガードレールに加えて、さらに有効と考えられる **未実装の候補** を整理する。
いずれも `rules/*.json` への追記（必要なら `builtins.sh` への関数追加）で実装できる設計としている。
優先度は「事故の起きやすさ × 影響の大きさ」で評価した目安。

実装済みのルール一覧は [01-overview.md](01-overview.md) を、判定ロジックの仕様は [03-rules-spec.md](03-rules-spec.md) を参照する。

## コマンド系（deny-commands.json で対応可能）

| 優先 | ID 案 | 防ぐ操作 | 例 | 備考 |
| --- | --- | --- | --- | --- |
| 中 | `curl-post-secrets` | 機密の外部送信（漏洩） | `curl -d "$AWS_SECRET..." http://...` | 検知は限定的だが代表パターンは捕捉可 |
| 中 | `package-install-global-sudo` | グローバル/sudo でのパッケージ導入 | `sudo npm i -g`, `pip install --user` 越え | 環境汚染 |
| 中 | `eval-base64` | 難読化されたコード実行 | `eval "$(echo ... \| base64 -d)"` | 回避の温床 |
| 低 | `kill-9-broad` | 広範なプロセス kill | `kill -9 -1`, `pkill -9 .` | 稼働中プロセス巻き込み |

## ファイル系（deny-files.json で対応可能）

| 優先 | ID 案 | 対象 | 備考 |
| --- | --- | --- | --- |
| 中 | `system-config-write` | `/etc/**`, `/usr/**`, `/boot/**` への write | システム設定の破壊防止 |
| 中 | `browser-profile` | ブラウザの保存資格情報 DB | Cookie/パスワード窃取防止 |
| 低 | `lockfile-write`（任意） | `package-lock.json` 等への不用意な write | 誤更新防止（運用次第で外す） |

## 設計上の検討事項（実装前に決めるべきこと）

### 除外（allow-list）の仕組み

現状のルールは deny のみで、除外は「パターンを十分に限定する」ことで対応している
（例: `dotenv` ルールは `.env` 完全一致とし、Git 管理対象の `.env.example` 等を最初から対象に含めない）。

パターンの限定だけでは表現しづらい「広く一致させたいが一部だけ許可したい」ケースが出てきた場合に備え、
ルールへ `exceptions`（除外パターン）を追加できる拡張を検討する。

```jsonc
{
  "id": "some-broad-rule",
  "patterns": ["**/config/**"],
  "exceptions": ["**/config/public/**"],   // ← 検討（広く deny しつつ一部を許可）
  "operations": ["read", "write"]
}
```

優先度: 中。誤検知で開発体験を損なう箇所が出てから入れてもよい。

### ルールのスコープ/重大度

`severity`（`block` / `warn`）を導入し、`warn` はブロックせず警告のみ（Claude は `additionalContext`、
Cursor は `permission: ask`）にする運用を検討する。段階的導入や、誤検知が怖いルールに有用。

### 監査ログ

deny が発生した際に、日時・エージェント・ルールID・対象を追記ログとして残す（`logs/` か syslog）。
インシデント分析・ルール改善に使う。書き込み先の権限と肥大化対策に注意。

### ルール配布・更新

複数リポジトリ/メンバーへ同一ルールを配るには、本リポジトリを git submodule か npm/OCI パッケージ等として
配布する方式を検討する。`install.sh` はその参照を解決する。

## このドキュメントの位置づけ

ここに挙げた項目は **候補**。実装は優先度の高いものから、初期要件の実装が安定した後に着手する。
新たに必要なガードレールに気づいたら、まずこの表へ追記し、合意の上で `rules/*.json` に落とす。
