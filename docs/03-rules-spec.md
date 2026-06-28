# 03. ルールJSON仕様

禁止対象は `rules/` 配下のJSONで一元管理する。新しい禁止対象は原則 **このJSONへの追記のみ** で全エージェントへ反映される。

ルールは2種類:

- `rules/deny-files.json` … ファイルの read / write を禁止
- `rules/deny-commands.json` … シェルコマンドの実行を禁止

## deny-files.json

### スキーマ

```jsonc
{
  "version": 1,
  "description": "ファイル枠の説明",
  "rules": [
    {
      "id": "dotenv",                       // 一意なルールID（必須）
      "description": "人間向け説明",         // 必須
      "patterns": ["**/.env"],              // glob パターン配列（必須）
      "operations": ["read", "write"],      // 適用する操作（必須, read/write の部分集合）
      "action": "deny",                     // 現状 "deny" のみ（必須）
      "message": "ブロック時に表示する理由"  // 必須
    }
  ]
}
```

### glob パターンの仕様

- `**` … 任意の深さのディレクトリにマッチ
- `*` … パス区切り（`/`）を除く任意の文字列にマッチ
- 判定対象の `path` は絶対パスに正規化済みである前提
- 大文字小文字は区別する
- マッチは「パスのいずれかの部分」ではなく **パス全体** に対して行う。広く一致させたい場合は先頭に `**/` を付ける

実装方針: glob を正規表現へ変換して照合する（`core/lib/match_file.sh`）。`**/` → `(.*/)?`、`*` → `[^/]*` への変換を基本とする。

### 追加例

新しく `*.keystore` を read/write 禁止にする場合、`rules` 配列へ以下を追記するだけでよい。

```json
{
  "id": "keystore",
  "description": "Java/Android のキーストア",
  "patterns": ["**/*.keystore", "**/*.jks"],
  "operations": ["read", "write"],
  "action": "deny",
  "message": "キーストアファイルへのアクセスは禁止されています。"
}
```

## deny-commands.json

### スキーマ

```jsonc
{
  "version": 1,
  "description": "コマンド枠の説明",
  "rules": [
    {
      "id": "curl-pipe-shell",                 // 一意なルールID（必須）
      "description": "人間向け説明",            // 必須
      "category": "remote-code-execution",      // 任意の分類タグ
      "match": {
        "type": "regex",                        // "regex" または "builtin"（必須）
        "pattern": "(curl|wget)\\b[^|]*\\|..."  // type=regex のとき必須
        // "evaluator": "rm_wildcard_outside_home"  // type=builtin のとき必須
      },
      "action": "deny",                         // 現状 "deny" のみ（必須）
      "message": "ブロック時に表示する理由"      // 必須
    }
  ]
}
```

### match.type == "regex"

- `command`（コマンド文字列全体）に対して正規表現で照合する
- 照合エンジンは `grep -E`（POSIX 拡張正規表現）を基準とする。JSON内のバックスラッシュは二重にエスケープすること
- 大文字小文字は区別する（必要なら `[Cc]url` のように明示）

> 注意: 正規表現ベースの判定はバイパス（空白・改行・変数経由・別名コマンド等）に弱い。
> ガードレールは「うっかり実行」を防ぐ多層防御の1層であり、悪意ある回避を完全に防ぐものではない、という前提を保つ。

### match.type == "builtin"

正規表現で表現しづらい判定（パスの所在判定など）は、`core/lib/builtins.sh` に評価関数を実装し、
`evaluator` でその名前を指定する。関数は `command` / `cwd` / `home` を受け取り、真（該当=deny）か偽を返す。

#### 定義済み builtin: `rm_wildcard_outside_home`

「ユーザーディレクトリ（`$HOME`）以下以外での、ワイルドカードを含む `rm`」を deny する。

判定ロジック（実装の指針）:

1. `command` を解析し、`rm` 呼び出しが含まれるか判定する。コマンド区切り（`;`, `&&`, `|`）に加えて、
   コマンド置換 `$(...)` ・バックティック・サブシェル `(...)` の境界も区切りに変換し、それらの内側の `rm` も検査する。
2. その `rm` の対象引数に **ワイルドカード**（`*`, `?`, `[`）が含まれるか判定する。
3. 含まれる場合、対象パスの解決先が `$HOME` 配下かを判定する:
   - 絶対パスならそのパスで判定
   - 相対パスなら `cwd` を基準に解決して判定
4. `$HOME` 配下に収まらない対象が1つでもあれば → **該当（deny）**。
5. 判定に必要な情報が欠落して安全側に倒せない場合は、fail-safe ポリシー（[02](02-architecture.md)）に従う。

#### 定義済み builtin: `reads_denied_file`

`cat`/`grep`/`less`/`head`/`tail` 等のコマンド、入力リダイレクト（`< file`）、`source`/`.` 経由で、
**`deny-files.json` の読み取り禁止ファイル**へアクセスしていれば deny する。
これにより、`Read` ツールだけでなくシェルコマンド経由のファイル読み取りも同じルールで防ぐ。

判定ロジック（実装の指針）:

1. `command` をセグメントへ分割する（`rm_wildcard_outside_home` と同様に区切り・サブシェルを展開）。
2. 各セグメントについて、先頭の `VAR=val` 代入と `sudo` を除去し、コマンド名を取り出す。
3. コマンド名が **読み取りコマンドの一覧**（`core/lib/builtins.sh` の `GUARDRAIL_READER_COMMANDS`）に含まれる場合、
   そのオペランド（フラグ以外の引数）をファイルパス候補とする。
4. 入力リダイレクト `< file` の対象、`source`/`.` の対象もパス候補に加える。
5. 各候補を `cwd` 基準で正規化し、`deny-files.json` の `read` 対象ルールに一致すれば → **該当（deny）**。

> 検査対象のコマンドを増やすには `GUARDRAIL_READER_COMMANDS` に追記する。
> 読み取りコマンドの網羅は本質的に不完全（[既知の制約](#既知の制約)）であり、多層防御の一層という位置づけ。
> なお `read` 操作を持たないルール（例: `guardrail-self-protection` は `write` のみ）は対象外なので、
> 書き込み禁止だが読み取りは許可するファイルの `cat` はブロックされない。
>
> builtin を増やす場合: `builtins.sh` に関数を追加し、テスト（[07](07-testing.md)）を必ず用意する。

#### 既知の制約

ガードレールはコマンド文字列を静的に解析するヒューリスティックであり、以下は原理的に検出できない。
これらは「うっかり実行」を防ぐ多層防御の一層という位置づけ（[01](01-overview.md)）の上で受容する。

- **`cd` をまたいだカレントディレクトリの追跡**: 1つのコマンド文字列内で `cd /tmp && rm *` のように
  移動した後の相対ワイルドカードは、Hook が渡す元の `cwd` を基準に判定するため、`$HOME` 内と誤判定しうる。
  実運用では各シェルコマンドが個別の Hook 呼び出し（個別の `cwd`）になるため影響は限定的。
- **変数・別名・エンコード経由の難読化**: `R=rm; $R -rf /*` や base64 デコード実行などは正規表現／静的解析では捕捉しない。

#### 定義済み regex: `docker-cli-volume-mount`

`docker` / `podman` / `docker compose` / `docker-compose` のコマンド文字列に、
CLI 上の `-v` / `--volume` / `--mount`（直前に空白があるトークン）が含まれる場合 deny する。
`docker-compose.yaml` に定義されたボリュームを使う `docker compose run --rm test` のような実行は対象外。

> compose ファイルへの書き込みや、yaml 内マウント定義の改ざんは本ルールの対象外。
> Hook は「その場で組み立てる ad-hoc マウント」の抑止を目的とする。

### 追加例（regex）

`chmod 777` を禁止する場合:

```json
{
  "id": "chmod-777",
  "description": "全権限付与の chmod を禁止",
  "category": "permission",
  "match": { "type": "regex", "pattern": "\\bchmod\\b[^\\n]*\\b777\\b" },
  "action": "deny",
  "message": "chmod 777 は禁止されています。必要最小限の権限を指定してください。"
}
```

## ルール変更時のチェックリスト

- [ ] `id` が既存と重複していないか
- [ ] `message` がエージェント/ユーザーにとって行動可能（なぜ止められたか・どうすべきか）か
- [ ] regex の場合、JSON エスケープ（`\\`）が正しいか
- [ ] 対応するテストケース（該当する/しない両方）を `tests/` に追加したか
- [ ] 想定外の誤検知（false positive）が広すぎないか
