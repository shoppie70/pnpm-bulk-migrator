# pnpm-bulk-migrator

> ワークスペース配下の Node.js プロジェクトを再帰的に自動検出し、npm / yarn から pnpm への移行と Git コミット・プッシュまでを一括実行する CLI ツール。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![pnpm](https://img.shields.io/badge/maintained%20with-pnpm-cc00ff.svg?style=flat-square)](https://pnpm.io/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg?style=flat-square)]()

開発フォルダを指定するだけで、散らばった複数のプロジェクトを高速に `pnpm` へ切り替え、重複した `node_modules` によるディスク消費を大幅に削減します。各リポジトリの Git 同期（ロックファイルのコミット＆リモートプッシュ）までワンストップで完結します。

---

## 開発の背景（作った理由）

Web 開発を続けていると、プロジェクトごとに作られる **`node_modules`** がストレージを圧迫し、気づけば PC の空き容量が残り数百 MB という危険水域に達してしまうことがあります。

従来の `npm` や `yarn` (v1) は、React や Next.js といった巨大な同一パッケージをプロジェクトごとに丸ごとディスクへ複製します。プロジェクトが 20 個、30 個と増えるにつれて、数十〜数百 GB もの容量が重複ファイルだけで失われていきます。

### pnpm なら容量を劇的に節約できる
**`pnpm`** は、マシン全体で同一バージョンのパッケージを 1 箇所（グローバルストア）にのみ保存し、各プロジェクトの `node_modules` にはそこへの **ハードリンク** を貼る設計になっています。  
これにより、プロジェクトをいくつ作っても **パッケージ実体の容量消費は 1 回分** で済み、ディスク容量を劇的に節約できます。

### しかし、手動での移行は骨が折れる
過去に作成した大量のプロジェクトを 1 つずつ手作業で移行しようとすると：

1. 各フォルダへ `cd` で移動
2. `node_modules` と古い lockfile を削除
3. `pnpm import` で依存関係のバージョンを再現
4. `pnpm install` でハードリンクを再構築
5. esbuild 等のビルドスクリプト承認エラーの解決
6. `git add / commit / push` を実行

…という手順を何十回も繰り返す必要があり、現実的ではありません。

そこで、**「指定した開発ディレクトリ配下を全探索し、安全確認・バージョン維持・ビルドスクリプト自動承認・Git リモート同期までを全自動で行えるツール」** として本ツールを開発しました。

---

## 主な機能

- **再帰的なプロジェクト自動検出**  
  指定したディレクトリ配下の `package.json` を再帰的にスキャンして一覧化します。
- **スマートな誤検出除外フィルタ**  
  PHP (Laravel) の `vendor/` や Python の `.venv/`、`.git/`、ビルド生成物 (`.next/`, `dist/`) などの内部に含まれる `package.json` は自動で除外します。
- **既存バージョンの厳密な再現 (`pnpm import`)**  
  既存の `package-lock.json` や `yarn.lock` を読み取って `pnpm-lock.yaml` を生成するため、意図しないライブラリのバージョンアップ（依存関係の破壊）を防ぎます。
- **ビルドスクリプト自動承認 (`pnpm approve-builds`)**  
  pnpm v10 以降でブロックされる `esbuild` や `@tailwindcss/oxide` などのネイティブバイナリビルドスクリプトを自動承認し、非対話でもインストールを完遂させます。
- **Git ロックファイルのピンポイント同期**  
  `pnpm-lock.yaml`（新規生成）、`package-lock.json` / `yarn.lock`（削除）のみをステージングしてコミット・プッシュします。作業途中の別ファイル（未コミットのソースコード）を巻き込む事故を防ぎます。
- **ドライラン対応 (`--dry-run`)**  
  ファイル変更を行わずに、対象プロジェクトの一覧と現在のパッケージマネージャ（npm / yarn / pnpm）を事前に確認できます。

---

## インストール

リポジトリをクローンし、スクリプトに実行権限を付与します：

```bash
git clone https://github.com/shoppie70/pnpm-bulk-migrator.git
cd pnpm-bulk-migrator
chmod +x migrate-to-pnpm.sh
```

---

## 使い方

### 基本的な実行方法

移行したい開発ディレクトリのパスを引数に指定して実行します：

```bash
./migrate-to-pnpm.sh ~/Projects
```

実行すると検出されたプロジェクト一覧が表示され、処理の続行および Git の自動操作（プッシュまで行うか、コミットのみか等）を選択できます。

### コマンドラインオプション

```text
使用方法: ./migrate-to-pnpm.sh [対象ディレクトリ] [オプション]

オプション:
  --dry-run    ファイル変更を行わず、対象プロジェクト一覧のみ表示
  --push       移行完了後、Git コミットおよびリモートへのプッシュまで全自動実行
  --commit     移行完了後、Git コミットのみ自動実行（プッシュは行わない）
  -y, --yes    確認プロンプトをスキップして即座に実行
  -h, --help   ヘルプメッセージを表示
```

### 実行例

**対象プロジェクトを事前に確認する（変更なし）：**
```bash
./migrate-to-pnpm.sh ~/Projects --dry-run
```

**特定のサブフォルダ配下をプッシュまで全自動で行う：**
```bash
./migrate-to-pnpm.sh ~/Projects/apps --push -y
```

**Git コミットは行わず、ローカルのファイル移行のみ行う：**
```bash
./migrate-to-pnpm.sh ~/Projects
# プロンプトで [n] を選択
```

---

## ターミナル実行ログ例

```text
==========================================================
 🚀 pnpm 移行スクリプト (Git連携対応)
 対象ディレクトリ: ~/Projects
==========================================================
🔍 プロジェクト（package.json）を検索中...

📋 見つかったプロジェクト一覧 (8 件):
----------------------------------------------------------
 [1/8] [Git] ~/Projects/frontend-app (📦 npm)
 [2/8] [Git] ~/Projects/api-service (📦 npm)
 [3/8] [Git] ~/Projects/admin-dashboard (🧶 yarn)
 [4/8] [Git] ~/Projects/landing-page (📦 npm)
 [5/8] [Git] ~/Projects/mobile-client (✅ pnpm 導入済み)
 [6/8] [Git] ~/Projects/shared-utils (📦 npm)
 [7/8] [Git] ~/Projects/blog (📦 npm)
 [8/8] [Git] ~/Projects/docs-site (📦 npm)
----------------------------------------------------------

Gitの自動操作を選択してください:
  [p] コミット＆プッシュまで自動で行う (推奨)
  [c] コミットのみ自動で行う（プッシュは手動）
  [n] Git操作は行わない（ファイル変更のみ）
選択 (p/c/n) [デフォルト: p]: p

⚠️ 上記のプロジェクトを pnpm へ移行しますか？ (y/N): y

🚀 移行処理を開始します (Git連携: push)...

[1/8] 処理中: ~/Projects/frontend-app
  🔄 既存の lockfile から pnpm-lock.yaml を生成中 (pnpm import)...
  🧹 古いファイル (node_modules, lockfile) を削除中...
  📦 pnpm install を実行中...
  ✅ pnpm 移行完了！
  📝 Git コミット完了: 'chore: migrate package manager to pnpm'
  ⬆️ Git プッシュ中 (origin main)...
  🚀 プッシュ完了！

==========================================================
 🎉 すべての処理が終了しました！
 成功: 7 件
 スキップ (移行済み): 1 件
 失敗: 0 件
==========================================================
```

---

## 安全への配慮

> [!IMPORTANT]
> **作業中コードの誤コミット防止**  
> `git add .` のような一括ステージングは行いません。  
> `pnpm-lock.yaml`（新規追加）、`package-lock.json` / `yarn.lock`（削除）、および `package.json` のみをピンポイントでステージングします。作業途中のソースコードが誤ってコミット・プッシュされる心配はありません。

> [!NOTE]
> **外部テンプレート等への権限ガード**  
> 上流の OSS テンプレートなどをフォークせずにクローンしている場合、書き込み権限がないリモートへのプッシュは自動的に検知されて安全にスキップされます。後続のプロジェクト処理が中断することはありません。

---

## 動作要件

* **macOS** または **Linux** (Bash / Zsh)
* **Node.js** (v18 以上推奨)
* **pnpm** (v9 以上、`pnpm setup` 済みであること)
* **Git** (Git 連携機能を使用する場合)
