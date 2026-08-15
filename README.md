# darask-paint-iopaint — Darask Paint 用 AI 修復プラグイン

[Darask Paint](https://github.com/daraskme/darask-paint) の「AI 修復(IOpaint)」メニューから使う、
ローカル AI インペインティングサーバのプラグインリポジトリです。

エンジンは [daraskme/IOpaint](https://github.com/daraskme/IOpaint)
([Sanster/IOPaint](https://github.com/Sanster/IOPaint) のフォーク、Apache-2.0)。
このリポジトリは「Darask Paint から使うためのランチャーとマニフェスト」を提供する薄いアダプタで、
エンジン本体は IOpaint フォークのリリース wheel をそのまま使います(コードの二重管理をしない)。

## 仕組み

```
Darask Paint (Rust, 単一exe)
   │  選択範囲の画像 + マスク (HTTP POST /api/v1/inpaint, 127.0.0.1 限定)
   ▼
darask-plugin.bat → IOpaint サーバ (Python, LaMa モデル, ポート 8423)
   │  修復済み画像
   ▼
Darask Paint がアクティブレイヤーの選択範囲だけに書き戻し(1 回の元に戻す単位)
```

Darask Paint 本体は依存を増やさず高速起動のまま。AI はこのプラグインを起動したときだけ使えます。

## 使い方

1. `darask-plugin.bat` をダブルクリック
   - 初回のみ: uv の導入 → Python 環境作成 → PyTorch(NVIDIA GPU があれば CUDA 12.8、なければ CPU)
     → IOpaint リリース wheel のインストール(数分)。環境は `%LOCALAPPDATA%\IOPaint` に作られ、
     IOpaint 単体の `IOPaint-OneClick.bat` と共有されます(二重インストールなし)。
   - 初回起動時に LaMa モデル(約 200MB)が自動ダウンロードされます。
2. Darask Paint で修復したい範囲を選択(矩形/楕円/なげなわ/自動選択)
3. メニューの「**AI 修復(IOpaint)…**」を実行
4. プラグインの黒い窓を閉じればサーバ停止(Darask Paint 本体はプラグインなしでも全機能動作)

- サーバは `127.0.0.1:8423` で待ち受けます(ローカル専用。外部には一切公開されません)。
- Darask Paint 側の接続先は設定ダイアログ(Ctrl+K)で変更できます。
- オフラインで軽く済ませたい場合は、本体内蔵の「選択範囲を修復」(非 AI)も使えます。

## 動作要件

| 環境 | 目安 |
|---|---|
| NVIDIA GPU (VRAM 4GB+) | 快適(1 回あたり ~1 秒) |
| CPU のみ | 動作可(1 回あたり数秒〜数十秒) |

## ライセンス

Apache-2.0(エンジンの IOPaint に準拠。`LICENSE` 参照)。
