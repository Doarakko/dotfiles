#!/bin/bash

# awesome-claude-code-subagents更新スクリプト

set -e

echo "🚀 Starting awesome-claude-code-subagents update..."

# リポジトリディレクトリに移動
cd ~/src

# リポジトリの存在確認と更新/クローン
if [ -d awesome-claude-code-subagents ]; then
  echo "📦 Updating existing repository..."
  cd awesome-claude-code-subagents
  git pull origin main
else
  echo "📥 Cloning repository..."
  git clone https://github.com/VoltAgent/awesome-claude-code-subagents.git
fi

# dotfilesディレクトリに移動
cd ~/src/dotfiles

# 古いサブエージェントを削除
echo "🗑️  Removing old subagents..."
rm -rf .claude/agents/awesome-claude-code-subagents

# 最新のサブエージェントをコピー
echo "📋 Copying latest subagents..."
cp -r ~/src/awesome-claude-code-subagents/categories .claude/agents/awesome-claude-code-subagents

# 確認
if [ -d .claude/agents/awesome-claude-code-subagents ]; then
  CATEGORY_COUNT=$(ls -1 .claude/agents/awesome-claude-code-subagents | wc -l | tr -d ' ')
  echo "✅ Successfully updated! Found ${CATEGORY_COUNT} categories."
else
  echo "❌ Update failed. Please check the error messages above."
  exit 1
fi
