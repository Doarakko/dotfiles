# Gemini ウェブ検索コマンド

Gemini AIを使用してGoogle検索を実行し、結果を要約して表示します。

## 使用方法
```bash
/gemini-search [検索クエリ]
```

## 例
```bash
/gemini-search "Claude Code の最新機能"
/gemini-search "TypeScript 5.0 新機能"
/gemini-search "Next.js App Router ベストプラクティス"
```

## 実装

```bash
#!/bin/bash

# gemini-cliがインストールされているかチェック
if ! command -v gemini &> /dev/null; then
    echo "❌ gemini-cliがインストールされていません"
    echo ""
    echo "📦 インストール手順:"
    echo "npm install -g @google/gemini-cli"
    echo ""
    echo "🔑 初期化手順:"
    echo "gemini"
    echo ""
    echo "詳細: https://zenn.dev/mizchi/articles/gemini-cli-for-google-search"
    exit 1
fi

# 検索クエリが指定されているかチェック
if [ -z "$1" ]; then
    echo "❌ 検索クエリを指定してください"
    echo ""
    echo "使用方法: /gemini-search [検索クエリ]"
    echo "例: /gemini-search \"Claude Code の最新機能\""
    exit 1
fi

# 検索クエリを組み立て
SEARCH_QUERY="$*"
echo "🔍 検索中: $SEARCH_QUERY"
echo ""

# 一時ファイルで結果をキャプチャ
TEMP_FILE=$(mktemp)

# Gemini AIでウェブ検索を実行
SEARCH_PROMPT="Webで「$SEARCH_QUERY」について調べて、以下の形式で回答してください：

## 🔍 検索結果の要約
[検索結果の主要なポイントを3-5個の箇条書きで]

## 📝 詳細情報
[重要な詳細情報や具体的な内容]

## 🔗 参考リンク
[関連する重要なURLがあれば記載]

## 📅 最新性
[情報の時期や最新性について]

回答は日本語で、読みやすく整理して提供してください。"

echo "🤖 Gemini AIで検索結果を分析中..."

# 検索を実行し、結果を一時ファイルに保存
if gemini -p "$SEARCH_PROMPT" > "$TEMP_FILE" 2>&1; then
    echo ""
    echo "=" | tr -d '\n' | while read; do printf "=%.0s" {1..60}; done
    echo ""
    echo "📊 検索結果まとめ"
    echo "=" | tr -d '\n' | while read; do printf "=%.0s" {1..60}; done
    echo ""
    
    # 結果を表示
    cat "$TEMP_FILE"
    
    echo ""
    echo "=" | tr -d '\n' | while read; do printf "=%.0s" {1..60}; done
    echo ""
    echo "✅ 検索完了 - クエリ: \"$SEARCH_QUERY\""
    echo "💡 より詳細な情報が必要な場合は、具体的なキーワードで再検索してください"
else
    echo ""
    echo "❌ 検索に失敗しました"
    echo ""
    echo "💡 トラブルシューティング:"
    echo "- gemini-cliの認証状態を確認: gemini"
    echo "- インターネット接続を確認"
    echo "- 検索クエリを変更して再試行"
    
    # エラー内容も表示
    if [ -s "$TEMP_FILE" ]; then
        echo ""
        echo "エラー詳細:"
        cat "$TEMP_FILE"
    fi
fi

# 一時ファイルを削除
rm -f "$TEMP_FILE"
```

## 特徴
- **リアルタイム検索**: Googleの最新情報にアクセス
- **AI要約**: Gemini AIが検索結果を整理して表示
- **統合された結果表示**: 検索結果を見やすい形式でまとめて表示
- **視覚的な区切り**: 結果の開始と終了を明確に示すボーダー表示
- **日本語対応**: 日本語クエリでの検索に最適化
- **エラーハンドリング**: 適切なエラーメッセージとトラブルシューティング
- **一時ファイル管理**: 結果を安全にキャプチャして表示

## 注意事項
- gemini-cliの初回使用時はGoogleアカウントでの認証が必要です
- 検索結果の品質はGemini AIの解析能力に依存します
- 大量の検索を行う場合はAPI使用量にご注意ください

## 関連コマンド
- `/pr-create`: プルリクエスト作成
- `/commit`: コミットとプッシュ
- `/review-diff`: コード差分レビュー