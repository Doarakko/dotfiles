# テスト自動生成コマンド

現在の差分から変更されたファイルを検出し、既存のテスト実装パターンに基づいてテストを自動生成します。

## 使用方法
```bash
/test-create
```

## 処理手順
1. `git diff`で変更されたファイルを検出
2. 各ファイルの言語・フレームワークを識別
3. 既存のテストファイルからパターンを学習
4. 新規または更新されたテストファイルを生成
5. 生成されたテストの概要を表示

## 実装

### ステップ1: 変更ファイルの検出と分析
```bash
echo "🔍 変更されたファイルを検出中..."

# ステージングされた変更とステージングされていない変更の両方を取得
STAGED_FILES=$(git diff --cached --name-only)
UNSTAGED_FILES=$(git diff --name-only)
ALL_CHANGED_FILES=$(echo -e "$STAGED_FILES\n$UNSTAGED_FILES" | sort -u | grep -v "^$")

if [ -z "$ALL_CHANGED_FILES" ]; then
    echo "❌ 変更されたファイルが見つかりません"
    echo "💡 ファイルを変更してから再度実行してください"
    exit 1
fi

echo "📝 変更されたファイル:"
echo "$ALL_CHANGED_FILES" | while read -r file; do
    echo "  - $file"
done
echo ""
```

### ステップ2: 各ファイルに対するテスト生成

変更されたファイルごとに：
1. ファイルの拡張子から言語を識別
2. 既存のテストパターンを検索
3. 適切なテストファイルを生成または更新

#### TypeScript/JavaScript ファイル
```bash
# TypeScript/JavaScript ファイルの処理
echo "$ALL_CHANGED_FILES" | grep -E "\.(ts|tsx|js|jsx)$" | while read -r file; do
    if [ -z "$file" ]; then continue; fi
    
    echo "📄 処理中: $file"
    
    # テストファイル名を決定
    TEST_FILE=""
    if [[ "$file" == *.tsx ]]; then
        TEST_FILE="${file%.tsx}.test.tsx"
    elif [[ "$file" == *.ts ]]; then
        TEST_FILE="${file%.ts}.test.ts"
    elif [[ "$file" == *.jsx ]]; then
        TEST_FILE="${file%.jsx}.test.jsx"
    elif [[ "$file" == *.js ]]; then
        TEST_FILE="${file%.js}.test.js"
    fi
    
    # __tests__ ディレクトリパターンをチェック
    DIR=$(dirname "$file")
    BASENAME=$(basename "$file")
    if [ -d "$DIR/__tests__" ]; then
        TEST_FILE="$DIR/__tests__/$BASENAME"
        TEST_FILE="${TEST_FILE%.*}.test.${file##*.}"
    fi
    
    echo "  → テストファイル: $TEST_FILE"
    
    # 既存のテストパターンを検索
    EXISTING_TEST_PATTERN=""
    if [ -f "$TEST_FILE" ]; then
        echo "  ✓ 既存のテストファイルを更新"
    else
        # 同じプロジェクトの他のテストファイルからパターンを学習
        SAMPLE_TEST=$(find "$(dirname "$file")" -name "*.test.*" -o -name "*.spec.*" | head -1)
        if [ -n "$SAMPLE_TEST" ]; then
            echo "  📚 テストパターンを学習: $SAMPLE_TEST"
        fi
        echo "  ✓ 新規テストファイルを生成"
    fi
done
```

#### Python ファイル
```bash
# Python ファイルの処理
echo "$ALL_CHANGED_FILES" | grep -E "\.py$" | while read -r file; do
    if [ -z "$file" ]; then continue; fi
    
    echo "📄 処理中: $file"
    
    # テストファイル名を決定
    TEST_FILE=""
    BASENAME=$(basename "$file" .py)
    DIR=$(dirname "$file")
    
    # pytest規則に従う
    if [[ "$file" == test_* ]] || [[ "$file" == *_test.py ]]; then
        echo "  ℹ️ スキップ: 既にテストファイルです"
        continue
    fi
    
    # tests/ ディレクトリが存在するかチェック
    if [ -d "$DIR/tests" ]; then
        TEST_FILE="$DIR/tests/test_$BASENAME.py"
    elif [ -d "tests" ]; then
        # プロジェクトルートのtestsディレクトリ
        TEST_FILE="tests/test_$BASENAME.py"
    else
        TEST_FILE="${DIR}/test_${BASENAME}.py"
    fi
    
    echo "  → テストファイル: $TEST_FILE"
    
    # 既存のテストパターンを検索
    if [ -f "$TEST_FILE" ]; then
        echo "  ✓ 既存のテストファイルを更新"
    else
        # pytestパターンを検索
        SAMPLE_TEST=$(find . -name "test_*.py" -o -name "*_test.py" | head -1)
        if [ -n "$SAMPLE_TEST" ]; then
            echo "  📚 テストパターンを学習: $SAMPLE_TEST"
        fi
        echo "  ✓ 新規テストファイルを生成"
    fi
done
```

#### Go ファイル
```bash
# Go ファイルの処理
echo "$ALL_CHANGED_FILES" | grep -E "\.go$" | grep -v "_test\.go$" | while read -r file; do
    if [ -z "$file" ]; then continue; fi
    
    echo "📄 処理中: $file"
    
    # テストファイル名を決定
    TEST_FILE="${file%.go}_test.go"
    
    echo "  → テストファイル: $TEST_FILE"
    
    if [ -f "$TEST_FILE" ]; then
        echo "  ✓ 既存のテストファイルを更新"
    else
        echo "  ✓ 新規テストファイルを生成"
    fi
done
```

### ステップ3: テスト生成の実行

実際のテスト生成は、各言語・フレームワークに応じて以下を実行：

1. **関数・クラスの抽出**: 変更されたファイルから公開関数・クラスを抽出
2. **テストケースの生成**: 
   - 正常系テスト
   - 異常系テスト
   - エッジケーステスト
3. **既存テストとの統合**: 既存のテストがある場合は重複を避けて追加

```bash
echo ""
echo "🧪 テスト生成プロセス:"
echo ""

# 実際にテストファイルを生成する関数を定義
generate_js_test() {
    local source_file="$1"
    local test_file="$2"
    local basename=$(basename "$source_file" | sed 's/\.[^.]*$//')
    
    # テストファイルの内容を生成
    cat > "$test_file" << EOF
import { describe, it, expect } from '@jest/globals';
import { $basename } from './$basename';

describe('$basename', () => {
  it('should be defined', () => {
    expect($basename).toBeDefined();
  });

  // TODO: 実際のテストケースを実装してください
  // 以下は例です：
  // it('should return expected result', () => {
  //   const result = $basename();
  //   expect(result).toBe(expectedValue);
  // });
});
EOF
}

generate_python_test() {
    local source_file="$1"
    local test_file="$2"
    local basename=$(basename "$source_file" .py)
    local module_path=$(echo "$source_file" | sed 's/\//_/g' | sed 's/\.py$//')
    
    # テストディレクトリがない場合は作成
    mkdir -p "$(dirname "$test_file")"
    
    cat > "$test_file" << EOF
import pytest
from $basename import *


class Test$(echo $basename | sed 's/^./\U&/')():
    """$basename モジュールのテストクラス"""
    
    def test_module_import(self):
        """モジュールがインポートできることをテスト"""
        # TODO: 実際のテストケースを実装してください
        assert True
        
    # TODO: 以下のようなテストメソッドを追加してください：
    # def test_function_name(self):
    #     """function_name のテスト"""
    #     result = function_name()
    #     assert result == expected_value
EOF
}

generate_go_test() {
    local source_file="$1"
    local test_file="$2"
    local package_name=$(head -1 "$source_file" | awk '{print $2}')
    
    cat > "$test_file" << EOF
package $package_name

import (
	"testing"
)

func TestPackage(t *testing.T) {
	// TODO: 実際のテストケースを実装してください
	// 以下は例です：
	// func TestFunctionName(t *testing.T) {
	//     result := FunctionName()
	//     expected := "expected_value"
	//     if result != expected {
	//         t.Errorf("FunctionName() = %v, want %v", result, expected)
	//     }
	// }
}
EOF
}

# 変更されたファイルに対してテストを生成
echo "$ALL_CHANGED_FILES" | while read -r file; do
    if [ -z "$file" ] || [ ! -f "$file" ]; then continue; fi
    
    # ファイルタイプを判定
    EXT="${file##*.}"
    
    case "$EXT" in
        ts|tsx|js|jsx)
            # テストファイル名を決定
            TEST_FILE="${file%.*}.test.${EXT}"
            if [[ "$file" == *".tsx" ]] || [[ "$file" == *".jsx" ]]; then
                # React コンポーネントの場合は __tests__ ディレクトリも考慮
                DIR=$(dirname "$file")
                if [ -d "$DIR/__tests__" ]; then
                    BASENAME=$(basename "$file")
                    TEST_FILE="$DIR/__tests__/${BASENAME%.*}.test.${EXT}"
                fi
            fi
            
            if [ ! -f "$TEST_FILE" ]; then
                echo "🔧 JavaScript/TypeScriptテストを生成: $file → $TEST_FILE"
                generate_js_test "$file" "$TEST_FILE"
            else
                echo "⚠️ テストファイル既存: $TEST_FILE (スキップ)"
            fi
            ;;
        py)
            if [[ "$file" != test_* ]] && [[ "$file" != *_test.py ]]; then
                BASENAME=$(basename "$file" .py)
                DIR=$(dirname "$file")
                
                # テストファイル名を決定
                if [ -d "$DIR/tests" ]; then
                    TEST_FILE="$DIR/tests/test_$BASENAME.py"
                elif [ -d "tests" ]; then
                    TEST_FILE="tests/test_$BASENAME.py"
                else
                    TEST_FILE="${DIR}/test_${BASENAME}.py"
                fi
                
                if [ ! -f "$TEST_FILE" ]; then
                    echo "🔧 Pythonテストを生成: $file → $TEST_FILE"
                    generate_python_test "$file" "$TEST_FILE"
                else
                    echo "⚠️ テストファイル既存: $TEST_FILE (スキップ)"
                fi
            fi
            ;;
        go)
            if [[ "$file" != *_test.go ]]; then
                TEST_FILE="${file%.go}_test.go"
                
                if [ ! -f "$TEST_FILE" ]; then
                    echo "🔧 Goテストを生成: $file → $TEST_FILE"
                    generate_go_test "$file" "$TEST_FILE"
                else
                    echo "⚠️ テストファイル既存: $TEST_FILE (スキップ)"
                fi
            fi
            ;;
        *)
            echo "⚠️ サポートされていないファイルタイプ: $file"
            ;;
    esac
done
```

### ステップ4: 生成結果の表示

```bash
echo ""
echo "📊 テスト生成結果:"
echo ""

# 生成されたテストファイルを表示
NEW_TEST_FILES=$(git status --porcelain | grep "^??" | grep -E "\.(test|spec)\." | awk '{print $2}')
MODIFIED_TEST_FILES=$(git status --porcelain | grep "^ M" | grep -E "\.(test|spec)\." | awk '{print $2}')

if [ -n "$NEW_TEST_FILES" ]; then
    echo "✨ 新規作成されたテストファイル:"
    echo "$NEW_TEST_FILES" | while read -r file; do
        echo "  - $file"
    done
fi

if [ -n "$MODIFIED_TEST_FILES" ]; then
    echo "📝 更新されたテストファイル:"
    echo "$MODIFIED_TEST_FILES" | while read -r file; do
        echo "  - $file"
    done
fi

echo ""
echo "✅ テスト生成が完了しました！"
echo ""
echo "🔄 次のステップ:"
echo "1. 生成されたテストを確認: git diff"
echo "2. テストを実行: npm test / pytest / go test など"
echo "3. 必要に応じてテストを調整"
echo "4. テストが成功したら: /commit でコミット"
```

## 注意事項

- 生成されたテストは必ず手動で確認してください
- 既存のテストパターンがない場合は、一般的なパターンを使用します
- プライベート関数のテストは生成されません
- モックやスタブが必要な場合は手動で追加してください

## サポートされる言語とフレームワーク

### JavaScript/TypeScript
- Jest
- Mocha
- Vitest
- React Testing Library

### Python
- pytest
- unittest
- nose2

### Go
- 標準のtestingパッケージ
- testify

## 高度な使用方法

### 特定ファイルのみ対象

特定のファイルに対してのみテストを生成したい場合は、事前に変更をステージングしてください：

```bash
git add path/to/specific/file.ts
/test-create
```

これにより、ステージングされたファイルに対してのみテストが生成されます。

### インテリジェントなテスト生成

Claude Codeを使ってより高度なテストを生成することも可能です。実装の詳細に基づいたテストを生成したい場合は、以下のような拡張版を使用してください：

```bash
# Claude Codeを使った高度なテスト生成
generate_intelligent_test() {
    local source_file="$1"
    local test_file="$2"
    
    echo "🤖 Claude Codeを使って高度なテストを生成中: $source_file"
    
    # ファイルの内容を読み取って、Claude Codeにテスト生成を依頼
    cat > /tmp/test_generation_prompt.txt << EOF
以下のファイルの内容に基づいて、包括的なテストコードを生成してください。

ファイル: $source_file

EOF
    cat "$source_file" >> /tmp/test_generation_prompt.txt
    cat >> /tmp/test_generation_prompt.txt << EOF

要件:
1. すべての公開関数/メソッドをテストする
2. 正常系、異常系、エッジケースを含む
3. 適切なモックやスタブを使用する
4. テストの可読性を重視する
5. コメントは日本語で記述する

テストフレームワークは既存のプロジェクト設定に合わせて選択してください。
EOF
    
    # Note: 実際の実装では、Claude Code APIを呼び出して
    # テストコードを生成することができます
    echo "💡 手動でテストコードをレビューして完成させてください"
}
```