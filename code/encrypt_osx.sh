#!/bin/bash

# 定义版本号
VERSION="v2.0-macos"

# 在脚本开始时输出版本信息
echo "RSA 密钥加密脚本 (macOS) - 版本: $VERSION"
echo "-------------------------------------"

# 定义变量
# 统一的 UUID 和密钥获取接口
KEY_AND_UUID_API_URL="https://enc.api.yangzihome.space" 
# 新的仅上传 UUID 的接口
UPLOAD_UUID_API_URL="https://enc.sunglowsec.com/keygen_uuid.php" 

# 定义临时文件名称
PUBLIC_KEY_FILE="public.pem"
PRIVATE_KEY_FILE="private.pem"
PUBLIC_FROM_PRIVATE_FILE="public_from_private.pem" # 用于密钥验证的临时文件

# 函数：错误处理和退出
function error_exit {
    local message="$1"
    echo "错误：$message" >&2 # 错误信息输出到 stderr
    cleanup
    exit 1
}

# 函数：清理临时文件
function cleanup {
    rm -f "$PUBLIC_KEY_FILE" "$PRIVATE_KEY_FILE" "$PUBLIC_FROM_PRIVATE_FILE" 2>/dev/null
    unset AES_KEY ENCRYPTED_KEY_BASE64 PUBLIC_KEY_PEM PRIVATE_KEY_PEM UUID
    echo "临时文件已清理。"
}

# 检查输入文件参数
if [ $# -eq 0 ]; then
    error_exit "请指定要加密的文件路径。用法: $0 <输入文件>"
fi

INPUT_FILE="$1"

# 检查文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    error_exit "文件 '$INPUT_FILE' 不存在"
fi

# 在原始文件名后直接添加 .enc 后缀
OUTPUT_FILE="${INPUT_FILE}.enc"

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo "警告：未找到 'jq' 命令。脚本将尝试使用 'sed' 进行JSON解析，但这可能不如 'jq' 健壮。" >&2
fi

# 从统一API获取UUID和RSA密钥对 (POST请求)
echo "正在从 $KEY_AND_UUID_API_URL 获取 UUID 和密钥对..."
API_RESPONSE=$(curl -s -X POST "$KEY_AND_UUID_API_URL" \
  -H "Content-Type: application/json" \
  -d '{}') # 即使不需要请求体，也要发送一个空的JSON对象

# 检查API响应
if [ -z "$API_RESPONSE" ]; then
    error_exit "无法从API获取密钥对或UUID，API响应为空。"
fi

# 检查API响应是否包含错误状态
if echo "$API_RESPONSE" | jq -e 'has("status") and .status == "error"' > /dev/null; then
    ERROR_MESSAGE=$(echo "$API_RESPONSE" | jq -r '.message')
    error_exit "API返回错误: $ERROR_MESSAGE (完整API响应: $API_RESPONSE)"
fi

# 提取公钥、私钥和UUID (优先使用 jq，否则使用 sed)
if command -v jq &> /dev/null; then
    PUBLIC_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.public_key_pem')
    PRIVATE_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.private_key_pem')
    UUID=$(echo "$API_RESPONSE" | jq -r '.uuid')
else
    # 针对不包含 jq 的情况，使用 sed 进行粗略解析 (假设 key_pem 值为多行字符串，且 \n 已转义为 \\n)
    # 这部分解析可能不如 jq 健壮，尤其是当JSON格式复杂时
    PUBLIC_KEY_PEM=$(echo "$API_RESPONSE" | sed -n 's/.*"public_key_pem":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
    PRIVATE_KEY_PEM=$(echo "$API_RESPONSE" | sed -n 's/.*"private_key_pem":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
    UUID=$(echo "$API_RESPONSE" | sed -n 's/.*"uuid":"\([^"]*\)".*/\1/p')
fi


# 检查提取结果
if [ -z "$PUBLIC_KEY_PEM" ] || [ -z "$PRIVATE_KEY_PEM" ] || [ -z "$UUID" ]; then
    error_exit "无法从API响应中提取公钥、私钥或UUID。API响应: $API_RESPONSE"
fi

# 保存密钥到文件
printf "%s" "$PUBLIC_KEY_PEM" > "$PUBLIC_KEY_FILE"
printf "%s" "$PRIVATE_KEY_PEM" > "$PRIVATE_KEY_FILE"
echo "RSA密钥对已成功获取并保存为 $PUBLIC_KEY_FILE 和 $PRIVATE_KEY_FILE。"


# 验证API返回的公钥和私钥是否匹配
echo "正在验证公钥和私钥匹配性..."
openssl rsa -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_FROM_PRIVATE_FILE" &>/dev/null
if [ $? -ne 0 ]; then
    echo "警告：无法从私钥生成公钥进行匹配验证，可能是密钥格式问题或OpenSSL版本差异。" >&2
    echo "请手动检查 private.pem 和 public.pem 的有效性。" >&2
else
    # 移除PEM头尾进行比较，避免换行符差异
    CLEAN_PUBLIC=$(awk 'NF { if($0 !~/^-/){print} }' "$PUBLIC_KEY_FILE")
    CLEAN_PUBLIC_FROM_PRIVATE=$(awk 'NF { if($0 !~/^-/){print} }' "$PUBLIC_FROM_PRIVATE_FILE")

    if [ "$CLEAN_PUBLIC" != "$CLEAN_PUBLIC_FROM_PRIVATE" ]; then
        error_exit "公钥和私钥不匹配！请检查API返回的密钥对。"
    else
        echo "公钥和私钥匹配验证通过。"
    fi
fi

# --- 重点修改部分开始 ---

# 向上传UUID的API发送UUID数据
echo "正在向 $UPLOAD_UUID_API_URL 上传 UUID..."
# 构建只包含 UUID 的 JSON
if command -v jq &> /dev/null; then
    JSON_DATA=$(jq -n --arg uid "$UUID" '{uuid: $uid}')
else
    # 手动构建 JSON (针对无 jq 环境)
    JSON_DATA="{\"uuid\":\"$UUID\"}"
fi


RESPONSE=$(curl -s -X POST "$UPLOAD_UUID_API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_DATA")

# 检查UUID上传API响应
# 期望 status 为 "success" 或 "warning" (如果UUID已存在)
if echo "$RESPONSE" | grep -q '"status":"success"' || echo "$RESPONSE" | grep -q '"status":"warning"'; then
  echo "UUID 上传成功或已存在。"
  echo "响应详情: $RESPONSE"
else
  error_exit "UUID 上传API返回非成功或警告状态。请求数据: $JSON_DATA 响应详情: $RESPONSE"
fi

# --- 重点修改部分结束 ---

echo "正在加密文件 '$INPUT_FILE'..."
# ---------------------------------------------------------------------
# 加密逻辑：确保输出格式与解密脚本兼容
# ---------------------------------------------------------------------

# 1. 生成随机AES密钥 (Base64编码，因为 openssl enc -pass pass: 期望的是字符串)
AES_KEY=$(openssl rand -base64 32)

# 2. 用AES加密文件内容，并将结果Base64编码
# -pbkdf2 和 -salt 确保加密强度，并在加密数据中包含盐值
# openssl base64 -e -A 用于输出单行Base64编码，没有换行符
ENCRYPTED_DATA_BASE64=$(openssl enc -aes-256-cbc -pbkdf2 -salt -in "$INPUT_FILE" -pass pass:"$AES_KEY" | openssl base64 -e -A)

if [ $? -ne 0 ]; then
  error_exit "文件AES加密失败"
fi

# 3. 用RSA公钥加密AES密钥，并将结果Base64编码
# openssl pkeyutl -encrypt 默认使用 PKCS#1 v1.5 padding。
# 需要明确指定 OAEP padding 和 SHA-256 哈希算法，以确保兼容性。
# openssl base64 -e -A 用于输出单行Base64编码，没有换行符
ENCRYPTED_KEY_BASE64=$(echo -n "$AES_KEY" | openssl pkeyutl -encrypt -pubin -inkey "$PUBLIC_KEY_FILE" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 | openssl base64 -e -A)

if [ $? -ne 0 ]; then
  error_exit "AES密钥RSA加密失败。请检查 $PUBLIC_KEY_FILE 是否有效，以及RSA填充模式是否正确。"
fi

# 4. 将所有部分按照特定格式写入输出文件
echo "---BEGIN_AES_KEY---" > "$OUTPUT_FILE"
echo "$ENCRYPTED_KEY_BASE64" >> "$OUTPUT_FILE"
echo "---END_AES_KEY---" >> "$OUTPUT_FILE"
echo "---BEGIN_ENCRYPTED_DATA---" >> "$OUTPUT_FILE"
echo "$ENCRYPTED_DATA_BASE64" >> "$OUTPUT_FILE"
echo "---END_ENCRYPTED_DATA---" >> "$OUTPUT_FILE"
echo "---END_ENCRYPTED_FILE_AND_KEY---" >> "$OUTPUT_FILE"

# ---------------------------------------------------------------------

echo "文件已成功加密为 '$OUTPUT_FILE'"
echo "关联的UUID: $UUID"

# 记录UUID信息到readme.txt
echo "加密的文件名称：$OUTPUT_FILE : $UUID" >> readme.txt

# 清理临时文件和密钥
cleanup

echo "加密完成！"
exit 0
