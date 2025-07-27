# 現在のブランチ表示コマンド

現在のブランチ名をシンプルに表示します。

## 使用方法
```bash
/branch-current
```

## 動作
現在のブランチ名を表示します。

## 実装

```bash
#!/bin/bash

# 現在のブランチ名を取得して表示
CURRENT_BRANCH=$(git branch --show-current)
echo "$CURRENT_BRANCH"
```

## 特徴
- **シンプル**: 現在のブランチ名のみを表示
- **高速**: 余計な処理なし

## 関連コマンド
- `/branch-main`: メインブランチに移動して更新
- `/branch-switch`: ブランチを切り替え
- `/branch-create`: 新しいブランチを作成
- `/commit`: 変更をコミット