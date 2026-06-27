# 08. 追加で検討すべきガードレール

初期要件（機密ファイル・curl パイプ・rm）以外に、ガードレールとして有効と考えられる項目を整理する。
いずれも `rules/*.json` への追記（必要なら `builtins.sh` への関数追加）で実装できる設計としている。
優先度は「事故の起きやすさ × 影響の大きさ」で評価した目安。

## コマンド系（deny-commands.json で対応可能）

| 優先 | ID 案 | 防ぐ操作 | 例 | 備考 |
| --- | --- | --- | --- | --- |
| 高 | `redirect-to-secret-file` | 機密ファイルへのシェル経由書き込み | `echo x > .env`, `tee .env`, `cp k .env` | Cursor の write 事前ブロック不可を補う（[05](05-agent-cursor.md)） |
| 高 | `git-push-force-protected` | 保護ブランチへの force push | `git push --force origin main` | builtin 推奨（対象ブランチ判定） |
| 高 | `git-reset-hard` / `git-clean-fdx` | 作業ツリーの破壊的操作 | `git reset --hard`, `git clean -fdx` | 未コミット変更の消失 |
| 高 | `dd-to-disk` | ブロックデバイスへの書き込み | `dd ... of=/dev/sd*` | 不可逆・致命的 |
| 高 | `mkfs` / `fdisk` | ファイルシステム/パーティション操作 | `mkfs.ext4 /dev/...` | 不可逆 |
| 中 | `chmod-777` / `chmod-recursive-root` | 過剰な権限付与 | `chmod -R 777 /` | 権限事故 |
| 中 | `curl-post-secrets` | 機密の外部送信（漏洩） | `curl -d "$AWS_SECRET..." http://...` | 検知は限定的だが代表パターンは捕捉可 |
| 中 | `package-install-global-sudo` | グローバル/sudo でのパッケージ導入 | `sudo npm i -g`, `pip install --user` 越え | 環境汚染 |
| 中 | `eval-base64` | 難読化されたコード実行 | `eval "$(echo ... | base64 -d)"` | 回避の温床 |
| 低 | `history-clear` | 監査証跡の消去 | `history -c`, `rm ~/.bash_history` | 証跡保全 |
| 低 | `kill-9-broad` | 広範なプロセス kill | `kill -9 -1`, `pkill -9 .` | 稼働中プロセス巻き込み |

## ファイル系（deny-files.json で対応可能）

| 優先 | ID 案 | 対象 | 備考 |
| --- | --- | --- | --- |
| 高 | （既定済）`dotenv` / `private-keys` / `cloud-credentials` / `ssh-dir` | `.env`, `*.pem`, `~/.aws`, `~/.ssh` | 実装済みルール |
| 中 | `system-config-write` | `/etc/**`, `/usr/**`, `/boot/**` への write | システム設定の破壊防止 |
| 中 | `browser-profile` | ブラウザの保存資格情報 DB | Cookie/パスワード窃取防止 |
| 中 | `history-files` | `**/.bash_history`, `**/.zsh_history` | 機密が含まれうる |
| 低 | `lockfile-write`（任意） | `package-lock.json` 等への不用意な write | 誤更新防止（運用次第で外す） |

## 設計上の検討事項（実装前に決めるべきこと）

### 除外（allow-list）の仕組み

現状のルールは deny のみ。`.env.example` のように「パターンには一致するが許可したい」ケースに備え、
ルールへ `exceptions`（除外パターン）を追加できる拡張を検討する。

```jsonc
{
  "id": "dotenv",
  "patterns": ["**/.env", "**/*.env"],
  "exceptions": ["**/.env.example", "**/.env.sample"],   // ← 検討
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
