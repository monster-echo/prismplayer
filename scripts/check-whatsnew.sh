#!/bin/bash
# 本地预检 whatsnew/*.txt:模拟 workflow "Set release notes (whatsnew)" 的读取与截断逻辑,
# 打 harmony-v* tag 前确认 newFeatures 能正确生成。publish job 用的是提交版文件,未提交的改动读不到。
# 用法: ./scripts/check-whatsnew.sh
set -euo pipefail

fail=0
shopt -s nullglob
FILES=(whatsnew/*.txt)
if [ ${#FILES[@]} -eq 0 ]; then
  echo "❌ 仓库根目录没有 whatsnew/*.txt(publish job 会静默跳过 whatsnew)"
  exit 1
fi

echo "== 提交状态 =="
for f in "${FILES[@]}"; do
  if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "❌ $f 未提交(publish job checkout 后读不到)"; fail=1
  elif [ -n "$(git diff HEAD -- "$f")" ]; then
    echo "❌ $f 有未提交的修改(publish job 用的是提交版,改动不会生效)"; fail=1
  else
    echo "✅ $f 已提交且与工作区一致"
  fi
done

echo
echo "== 内容预检(逐字模拟 workflow 逻辑) =="
for LANG_FILE in "${FILES[@]}"; do
  LANGCODE=$(basename "$LANG_FILE" .txt)
  if ! echo "$LANGCODE" | grep -qE '^[a-z]{2}(-[A-Z]{2})?$'; then
    echo "⚠️  语言码 '$LANGCODE' 不是常见格式(zh-CN/en-US),确认 AGC 应用已启用该语言"
  fi
  CONTENT=$(head -c 1500 "$LANG_FILE" | tr -d '\r')
  CHARS=${#CONTENT}
  BYTES=$(printf %s "$CONTENT" | wc -c | tr -d ' ')
  STATUS="ok"
  if [ "$CHARS" -gt 500 ]; then
    echo "⚠️  $LANG_FILE 超过 500 字(实际 $CHARS 字符),workflow 会截断到 500"
    STATUS="将截断"
    CONTENT="${CONTENT:0:500}"
  fi
  CR_LINES=$(grep -c $'\r' "$LANG_FILE" 2>/dev/null || true)
  if [ "${CR_LINES:-0}" -gt 0 ]; then
    echo "⚠️  $LANG_FILE 含 CRLF 行尾 $CR_LINES 行(workflow 会自动去 \r,建议本地转 LF)"
  fi
  PAYLOAD=$(jq -n --arg lang "$LANGCODE" --arg nf "$CONTENT" '{lang:$lang,newFeatures:$nf}')
  if ! echo "$PAYLOAD" | jq -e . >/dev/null 2>&1; then
    echo "❌ $LANG_FILE 生成的 payload 不是合法 JSON"; fail=1; continue
  fi
  echo "--- $LANG_FILE → lang=$LANGCODE [$STATUS] 字符:$CHARS 字节:$BYTES"
  echo "    将发送: $(echo "$PAYLOAD" | jq -c .)"
  echo "    预览:"
  echo "$PAYLOAD" | jq -r '.newFeatures' | sed 's/^/      /'
done

if [ "$fail" -ne 0 ]; then
  echo; echo "❌ 预检未通过,先修复上面标记的问题再打 tag"
  exit 1
fi
echo
echo "✅ whatsnew 预检通过,可以打 tag"
