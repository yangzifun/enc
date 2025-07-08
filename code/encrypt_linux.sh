#!/bin/bash

# 定义版本号
VERSION="v2.0-Linux" # 更新版本号以示修改

# 在脚本开始时输出版本信息
echo "RSA 密钥加密脚本 - 版本: $VERSION"
echo "-------------------------------------"

# 定义变量
# 将UUID和密钥获取的接口统一修改为 https://enc.api.yangzihome.space
KEY_AND_UUID_API_URL="https://enc.api.yangzihome.space" 
# 新的上传UUID的接口
UPLOAD_UUID_API_URL="https://encrypt.yangzihome.space/keygen_uuid.php" 

# 检查输入文件参数
if [ $# -eq 0 ]; then
    echo "错误：请指定要加密的文件路径"
    echo "用法: $0 <输入文件>"
    exit 1
fi

INPUT_FILE="$1"

# 检查文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "错误：文件 '$INPUT_FILE' 不存在"
    exit 1
fi

# 在原始文件名后直接添加 .enc 后缀
OUTPUT_FILE="${INPUT_FILE}.enc"

# 从统一API获取UUID和RSA密钥对 (POST请求)
echo "正在从 $KEY_AND_UUID_API_URL 获取 UUID 和密钥对..."
API_RESPONSE=$(curl -s -X POST "$KEY_AND_UUID_API_URL" \
  -H "Content-Type: application/json" \
  -d '{}') # 即使不需要请求体，也要发送一个空的JSON对象

# 检查API响应
if [ -z "$API_RESPONSE" ]; then
    echo "错误：无法从API获取密钥对或UUID，API响应为空。"
    exit 1
fi

# 检查API响应是否包含错误状态
if echo "$API_RESPONSE" | jq -e 'has("status") and .status == "error"' > /dev/null; then
    ERROR_MESSAGE=$(echo "$API_RESPONSE" | jq -r '.message')
    echo "错误：API返回错误: $ERROR_MESSAGE"
    echo "完整API响应: $API_RESPONSE"
    exit 1
fi

# 提取公钥、私钥和UUID
PUBLIC_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.public_key_pem')
PRIVATE_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.private_key_pem')
UUID=$(echo "$API_RESPONSE" | jq -r '.uuid')

# 检查提取结果
if [ -z "$PUBLIC_KEY_PEM" ] || [ -z "$PRIVATE_KEY_PEM" ] || [ -z "$UUID" ]; then
    echo "错误：无法从API响应中提取公钥、私钥或UUID。"
    echo "API响应: $API_RESPONSE"
    exit 1
fi

# 保存密钥到文件
echo "$PUBLIC_KEY_PEM" > public.pem
echo "$PRIVATE_KEY_PEM" > private.pem

# 验证API返回的公钥和私钥是否匹配 (可选，但推荐)
echo "正在验证公钥和私钥匹配性..."
openssl rsa -in private.pem -pubout -out public_from_private.pem &>/dev/null
if [ $? -ne 0 ]; then
    echo "警告：无法从私钥生成公钥进行匹配验证，可能是密钥格式问题或OpenSSL版本差异。"
    echo "请手动检查 private.pem 和 public.pem 的有效性。"
else
    # 移除PEM头尾进行比较，避免换行符差异
    CLEAN_PUBLIC=$(awk 'NF { if($0 !~/^-/){print} }' public.pem)
    CLEAN_PUBLIC_FROM_PRIVATE=$(awk 'NF { if($0 !~/^-/){print} }' public_from_private.pem)

    if [ "$CLEAN_PUBLIC" != "$CLEAN_PUBLIC_FROM_PRIVATE" ]; then
        echo "错误：公钥和私钥不匹配！"
        echo "public.pem 内容："
        cat public.pem
        echo "public_from_private.pem 内容："
        cat public_from_private.pem
        rm -f private.pem public.pem public_from_private.pem # 清理密钥文件
        exit 1
    else
        echo "公钥和私钥匹配验证通过。"
    fi
fi


# --- 重点修改部分开始 ---

# 向上传UUID的API发送UUID数据
echo "正在向 $UPLOAD_UUID_API_URL 上传 UUID..."
JSON_DATA=$(jq -n \
  --arg uid "$UUID" \
  '{uuid: $uid}')

RESPONSE=$(curl -s -X POST "$UPLOAD_UUID_API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_DATA")

# 检查UUID上传API响应
# 注意：这里我们期望 status 为 "success" 或 "warning" (如果UUID已存在)
if echo "$RESPONSE" | jq -e 'has("status") and (.status == "success" or .status == "warning")' > /dev/null; then
  echo "UUID 上传成功或已存在。"
  echo "响应详情: $RESPONSE"
else
  echo "错误：UUID 上传API返回非成功或警告状态。"
  echo "请求数据: $JSON_DATA"
  echo "响应详情: $RESPONSE"
  rm -f private.pem public.pem public_from_private.pem # 清理密钥文件
  exit 1
fi

# --- 重点修改部分结束 ---


echo "正在加密文件 '$INPUT_FILE'..."
# ---------------------------------------------------------------------
# 修正后的加密逻辑：确保输出格式与解密脚本兼容
# ---------------------------------------------------------------------

# 1. 生成随机AES密钥
# 使用Base64编码，便于传输
AES_KEY_RAW=$(openssl rand -base64 32) 
AES_KEY="$AES_KEY_RAW"

# 2. 用AES加密文件内容，并将结果Base64编码
ENCRYPTED_DATA_BASE64=$(openssl enc -aes-256-cbc -pbkdf2 -salt -in "$INPUT_FILE" -pass pass:"$AES_KEY" | base64 -w 0)

if [ $? -ne 0 ]; then
  echo "错误：文件AES加密失败"
  rm -f private.pem public.pem public_from_private.pem # 清理密钥文件
  exit 1
fi

# 3. 用RSA公钥加密AES密钥，并将结果Base64编码
# openssl pkeyutl -encrypt 默认使用 PKCS#1 v1.5 padding。
# 但你的Workers代码生成密钥时使用了 RSA-OAEP。
# 因此，这里需要明确指定 OAEP padding 和 SHA-256 哈希算法，以确保兼容性。
ENCRYPTED_KEY_BASE64=$(echo -n "$AES_KEY" | openssl pkeyutl -encrypt -pubin -inkey public.pem -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 | base64 -w 0)

if [ $? -ne 0 ]; then
  echo "错误：AES密钥RSA加密失败。请检查 public.pem 是否有效，以及RSA填充模式是否正确。"
  rm -f private.pem public.pem public_from_private.pem # 清理密钥文件
  exit 1
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
rm -f private.pem public.pem public_from_private.pem
unset AES_KEY
unset ENCRYPTED_KEY_BASE64
unset ENCRYPTED_DATA_BASE64

echo "加密完成！"
exit 0
