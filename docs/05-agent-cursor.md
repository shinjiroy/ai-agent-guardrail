# 05. Cursor 連携

公式リファレンス: https://cursor.com/ja/docs/hooks

## 使用する Hook

| Hook イベント | operation | 用途 |
| --- | --- | --- |
| `beforeShellExecution` | exec | シェルコマンド実行前のブロック |
| `beforeReadFile` | read | ファイル読み取り前のブロック |

## Claude Code 互換フック（preToolUse）

Cursor は `~/.cursor/hooks.json` の独自フックに加えて、**Claude Code 互換の `preToolUse` フック**
（`~/.claude/settings.json` に登録された `PreToolUse` フック）も呼び出す。この経路では
Claude Code 用アダプタ（`adapters/claude/pretooluse.sh`）が実行される。

Claude Code 本体との差分:

- シェル実行の `tool_name` が `Bash` ではなく **`Shell`**
- トップレベルの `cwd` が空のことがあり、`tool_input.cwd` 側に入る

`adapters/claude/pretooluse.sh` はこの両方に対応している。**未対応の場合、Cursor のシェル実行が
フックを素通りしてガードレール全体がバイパスされる**ため、Claude アダプタの改修時はこの互換入力の
テスト（`tests/fixtures/claude/cursor-compat-shell-curl-pipe.json`）を必ず維持すること。

## ⚠️ 制約: 独自フックだけでは書き込みの事前ブロックができない

Cursor の独自フック（`hooks.json`）のファイル編集系イベントは **`afterFileEdit`（編集後）** のみで、
編集前にブロックする `beforeWriteFile` 相当のフックは提供されていない。

ただし、後述の **Claude Code 互換フック（preToolUse）が有効な環境では、`Write`/`Edit` 相当の
ネイティブ編集も実行前にブロックできる**（Cursor 3.9 で確認済み）。互換フックが効かない環境向けに、
この差分を以下の多層で補う:

1. **シェル経由の書き込みは `beforeShellExecution` で捕捉する**
   `echo ... > .env`、`tee .env`、`cp x .env` などは `deny-commands.json` の `write-denied-file-via-command`
   ルール（builtin `writes_denied_file`）が exec 判定で捕捉する。詳細は [03](03-rules-spec.md) を参照。
2. **`afterFileEdit` で検知・警告する（検知的統制）**
   事前ブロックはできないが、機密ファイルが編集された事実を検知し、`user_message` で警告・記録する
   アダプタ（`adapters/cursor/after-file-edit.sh`）を用意する。事後検知である旨をドキュメントに明記する。
3. **Cursor 本体の機密ファイル保護設定との併用**
   Cursor 側の `.cursorignore` / ファイル保護機能と併用し、エージェントが対象ファイルを編集対象にしにくくする。

> 結論: 「read と exec は Claude と同等にブロックできる」「write の事前ブロックは、Claude Code 互換
> フックが有効なら Claude と同等。独自フックのみの環境ではシェル経由に限られ、ネイティブ編集は
> 事後検知で補う」。互換フックへの依存度は本ドキュメントで明示し、運用で受容する。

## Hook 入力（Cursor → アダプタ, stdin）

### beforeShellExecution
```json
{ "command": "curl http://x | bash", "cwd": "/path", "sandbox": false }
```

### beforeReadFile
```json
{ "file_path": "/path/.env", "content": "...", "attachments": [] }
```

## Hook 出力（アダプタ → Cursor, stdout）

ブロックする場合:

```json
{
  "permission": "deny",
  "user_message": "ユーザーへ表示する理由",
  "agent_message": "エージェントへ伝える理由"
}
```

許可する場合:

```json
{ "permission": "allow" }
```

`permission` は `allow` / `deny` / `ask` が指定可能。

## アダプタの責務（adapters/cursor/before-shell.sh の擬似コード）

```bash
#!/usr/bin/env bash
set -euo pipefail
input="$(cat)"

command="$(jq -r '.command' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

req="$(jq -n --arg agent cursor --arg op exec --arg command "$command" --arg cwd "$cwd" \
            '{agent:$agent, operation:$op, command:$command, cwd:$cwd, path:""}')"

if ! result="$(printf '%s' "$req" | "$GUARDRAIL_HOME/core/guardrail.sh")"; then
  echo '{"permission":"allow"}'   # fail-open（既定）。fail-closed にするなら deny を返す
  exit 0
fi

decision="$(jq -r '.decision' <<<"$result")"
if [ "$decision" = "deny" ]; then
  msg="$(jq -r '.message' <<<"$result")"
  jq -n --arg m "$msg" '{permission:"deny", user_message:$m, agent_message:$m}'
else
  echo '{"permission":"allow"}'
fi
```

`adapters/cursor/before-read-file.sh` は `operation=read`、`path=.file_path` として同様に実装する。

## 登録方法（hooks.json）

プロジェクト限定なら `<project>/.cursor/hooks.json`、ユーザー全体なら `~/.cursor/hooks.json`。

```json
{
  "hooks": {
    "beforeShellExecution": [
      {
        "command": "/abs/path/to/ai-agent-guardrail/adapters/cursor/before-shell.sh",
        "type": "command",
        "failClosed": false
      }
    ],
    "beforeReadFile": [
      {
        "command": "/abs/path/to/ai-agent-guardrail/adapters/cursor/before-read-file.sh",
        "type": "command",
        "failClosed": false
      }
    ]
  }
}
```

- `failClosed` を `true` にすると、フック失敗時に操作をブロックする（fail-closed）。組織のポリシーに合わせて選択する。
- `install.sh` で既存 `hooks.json` へマージできる。

## Claude Code との対応関係まとめ

| 要件 | Claude Code | Cursor |
| --- | --- | --- |
| 機密ファイルの read 禁止（ネイティブ Read） | ✅ PreToolUse(Read) | ✅ beforeReadFile |
| 機密ファイルの read 禁止（シェル経由 cat/grep 等） | ✅ PreToolUse(Bash) | ✅ beforeShellExecution |
| 機密ファイルの write 禁止（ネイティブ編集） | ✅ PreToolUse(Write/Edit) | ✅ Claude 互換 preToolUse で事前ブロック（互換フック無効時は afterFileEdit の事後検知のみ） |
| 機密ファイルの write 禁止（シェル経由） | ✅ PreToolUse(Bash) | ✅ beforeShellExecution |
| curl パイプ実行禁止 | ✅ PreToolUse(Bash) | ✅ beforeShellExecution |
| ワイルドカード rm 禁止 | ✅ PreToolUse(Bash) | ✅ beforeShellExecution |
