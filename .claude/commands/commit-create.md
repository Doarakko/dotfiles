# commitメッセージを作成

## 実行手順
1. `git status`でファイルを確認
2. [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)に従ってコミットを実行

## 形式の指定
- type(scope): subject の形式に従う
- タイトルは50文字以内、本文は72文字程度で改行
- 動詞は原形を使用（add, fix, updateなど）
- scope は原則記述するが、適切なものがない場合は省略可
- コミットメッセージは小文字で始める

## 実装とテストが含まれる場合の優先ルール
- 実装とテストコードが含まれている場合、typeはtestよりもfeat/fixを優先する
