#!/usr/bin/env bash

# ==============================================================================
# migrate-to-pnpm.sh
# 
# 指定フォルダ配下の Node.js プロジェクトを再帰的に検索し、
# 既存の npm / yarn から pnpm へ安全に移行するスクリプト。
#
# 主な機能:
#  - vendor / .venv / .git / node_modules などの誤検出を自動除外
#  - package-lock.json / yarn.lock から pnpm-lock.yaml を高精度に生成 (pnpm import)
#  - 重複した node_modules を削除し、pnpm によるハードリンク共有で容量を節約
#  - Git リポジトリを自動検知し、ロックファイルの変更を自動コミット＆プッシュ可能
#  - 実行前のドライラン (--dry-run) 対応
# ==============================================================================

set -u

# --- 設定・デフォルト値 ---
TARGET_DIR="${1:-.}"
DRY_RUN=false
AUTO_CONFIRM=false
GIT_ACTION="none"  # "none", "commit", "push"
COMMIT_MSG="chore: migrate package manager to pnpm"

# 引数解析
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      ;;
    --commit)
      GIT_ACTION="commit"
      ;;
    --push)
      GIT_ACTION="push"
      ;;
    --help|-h)
      echo "使用方法: $0 [対象ディレクトリ] [オプション]"
      echo ""
      echo "オプション:"
      echo "  --dry-run    実際には変更を加えず、対象プロジェクト一覧のみ表示"
      echo "  --commit     移行後に Git コミットまで自動実行"
      echo "  --push       移行後に Git コミット＆プッシュまで自動実行"
      echo "  -y, --yes    確認プロンプトを表示せず自動で実行"
      echo "  -h, --help   ヘルプを表示"
      echo ""
      echo "例:"
      echo "  $0 ~/Documents/Development/999_home --dry-run"
      echo "  $0 ~/Documents/Development/999_home --push"
      exit 0
      ;;
    *)
      if [[ "$arg" != -* ]]; then
        TARGET_DIR="$arg"
      fi
      ;;
  esac
done

TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")

if [ ! -d "$TARGET_DIR" ]; then
  echo "❌ エラー: 指定されたディレクトリが存在しません: $TARGET_DIR"
  exit 1
fi

echo "=========================================================="
echo " 🚀 pnpm 移行スクリプト (Git連携対応)"
echo " 対象ディレクトリ: $TARGET_DIR"
if [ "$DRY_RUN" = true ]; then
  echo " 実行モード: DRY-RUN（変更は行いません）"
fi
echo "=========================================================="

# pnpm コマンドの存在確認
if ! command -v pnpm &> /dev/null; then
  echo "❌ エラー: 'pnpm' コマンドが見つかりません。"
  echo "先に pnpm をインストールしてください。"
  exit 1
fi

echo "🔍 プロジェクト（package.json）を検索中..."

# 除外フォルダを指定して package.json を探索
# 除外: node_modules, .git, vendor, .venv, venv, env, dist, build, .next, .nuxt, .cache
project_dirs=()

while IFS= read -r pkg_path; do
  dir=$(dirname "$pkg_path")
  project_dirs+=("$dir")
done < <(find "$TARGET_DIR" \
  \( -name "node_modules" \
  -o -name ".git" \
  -o -name "vendor" \
  -o -name ".venv" \
  -o -name "venv" \
  -o -name "env" \
  -o -name "dist" \
  -o -name "build" \
  -o -name ".next" \
  -o -name ".nuxt" \
  -o -name ".cache" \) -prune \
  -o -name "package.json" -print)

total_projects=${#project_dirs[@]}

if [ "$total_projects" -eq 0 ]; then
  echo "ℹ️ 対象の Node.js プロジェクトは見つかりませんでした。"
  exit 0
fi

echo ""
echo "📋 見つかったプロジェクト一覧 ($total_projects 件):"
echo "----------------------------------------------------------"
for i in "${!project_dirs[@]}"; do
  dir="${project_dirs[$i]}"
  status="未移行"
  is_git="[非Git]"
  
  if [ -d "$dir/.git" ] || (cd "$dir" 2>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null); then
    is_git="[Git]"
  fi

  if [ -f "$dir/pnpm-lock.yaml" ]; then
    status="✅ pnpm 導入済み"
  elif [ -f "$dir/package-lock.json" ]; then
    status="📦 npm"
  elif [ -f "$dir/yarn.lock" ]; then
    status="🧶 yarn"
  fi
  echo " [$((i + 1))/$total_projects] $is_git $dir ($status)"
done
echo "----------------------------------------------------------"

if [ "$DRY_RUN" = true ]; then
  echo "✨ ドライランが完了しました。ファイルは一切変更されていません。"
  exit 0
fi

# Git操作の確認（引数で指定されていない場合）
if [ "$GIT_ACTION" = "none" ] && [ "$AUTO_CONFIRM" = false ]; then
  echo ""
  echo "Gitの自動操作を選択してください:"
  echo "  [p] コミット＆プッシュまで自動で行う (推奨)"
  echo "  [c] コミットのみ自動で行う（プッシュは手動）"
  echo "  [n] Git操作は行わない（ファイル変更のみ）"
  read -p "選択 (p/c/n) [デフォルト: p]: " git_choice
  git_choice=${git_choice:-p}
  case "$git_choice" in
    [pP]*) GIT_ACTION="push" ;;
    [cC]*) GIT_ACTION="commit" ;;
    *)     GIT_ACTION="none" ;;
  esac
fi

if [ "$AUTO_CONFIRM" = false ]; then
  echo ""
  read -p "⚠️ 上記のプロジェクトを pnpm へ移行しますか？ (y/N): " answer
  if [[ "$answer" != [yY] && "$answer" != [yY][eE][sS] ]]; then
    echo "🚫 移行をキャンセルしました。"
    exit 0
  fi
fi

echo ""
echo "🚀 移行処理を開始します (Git連携: $GIT_ACTION)..."
echo ""

success_count=0
skipped_count=0
failed_count=0

for i in "${!project_dirs[@]}"; do
  dir="${project_dirs[$i]}"
  echo "[$((i + 1))/$total_projects] 処理中: $dir"

  cd "$dir" || {
    echo "  ❌ ディレクトリに移動できませんでした: $dir"
    failed_count=$((failed_count + 1))
    continue
  }

  # 既に pnpm-lock.yaml があり、package-lock / yarn.lock がない場合はスキップ
  if [ -f "pnpm-lock.yaml" ] && [ ! -f "package-lock.json" ] && [ ! -f "yarn.lock" ]; then
    echo "  ⏩ すでに pnpm に移行済みのためスキップします。"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # 既存の lockfile から pnpm-lock.yaml を生成（バージョンの完全再現）
  if [ -f "package-lock.json" ] || [ -f "yarn.lock" ]; then
    echo "  🔄 既存の lockfile から pnpm-lock.yaml を生成中 (pnpm import)..."
    if ! pnpm import 2>/dev/null; then
      echo "  ⚠️ pnpm import がスキップされたため、新規に依存関係を解決します。"
    fi
  fi

  # 古いロックファイルと node_modules の削除
  echo "  🧹 古いファイル (node_modules, lockfile) を削除中..."
  rm -rf node_modules package-lock.json yarn.lock

  # pnpm install でハードリンク構築
  echo "  📦 pnpm install を実行中..."
  pnpm approve-builds --all 2>/dev/null || true
  if pnpm install; then
    echo "  ✅ pnpm 移行完了！"
    success_count=$((success_count + 1))

    # --- Git コミット & プッシュ処理 ---
    if [ "$GIT_ACTION" != "none" ]; then
      if git rev-parse --is-inside-work-tree &>/dev/null; then
        # 他の作業中ファイルを誤ってコミットしないよう、ロックファイル関連のみピンポイントでステージング
        for f in package-lock.json yarn.lock pnpm-lock.yaml pnpm-workspace.yaml package.json; do
          if [ -e "$f" ] || git ls-files --error-unmatch "$f" &>/dev/null; then
            git add "$f" 2>/dev/null || true
          fi
        done

        # ステージングされた差分がある場合のみコミット
        if ! git diff --cached --quiet 2>/dev/null; then
          git commit -m "$COMMIT_MSG"
          echo "  📝 Git コミット完了: '$COMMIT_MSG'"

          if [ "$GIT_ACTION" = "push" ]; then
            current_branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
            current_remote=$(git remote | head -n 1)

            if [ -n "$current_remote" ] && [ -n "$current_branch" ]; then
              echo "  ⬆️ Git プッシュ中 ($current_remote $current_branch)..."
              # もしリモート先行がある場合は自動で pull してプッシュを試みる
              if ! git push "$current_remote" "$current_branch" 2>/dev/null; then
                echo "  🔄 リモートの最新を取得してマージします..."
                git pull --no-edit "$current_remote" "$current_branch" 2>/dev/null || true
                git push "$current_remote" "$current_branch" 2>&1 | sed 's/^/    /' || echo "  ⚠️ プッシュ失敗（手動でプッシュしてください）"
              else
                echo "  🚀 プッシュ完了！"
              fi
            else
              echo "  ℹ️ リモートリポジトリが設定されていないためプッシュをスキップしました。"
            fi
          fi
        else
          echo "  ℹ️ Git 差分がないためコミットをスキップしました。"
        fi
      fi
    fi

  else
    echo "  ❌ pnpm install でエラーが発生しました。"
    failed_count=$((failed_count + 1))
  fi
  echo ""
done

echo "=========================================================="
echo " 🎉 すべての処理が終了しました！"
echo " 成功: $success_count 件"
echo " スキップ (移行済み): $skipped_count 件"
echo " 失敗: $failed_count 件"
echo "=========================================================="
