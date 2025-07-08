#!/bin/bash

# 定义版本号
VERSION="v2.0-macos-folder"

# 在脚本开始时输出版本信息
echo "RSA 密钥文件夹加密脚本 (macOS) - 版本: $VERSION"
echo "-------------------------------------"

# 定义变量
# 统一的 UUID 和密钥获取接口
KEY_AND_UUID_API_URL="https://rsa-uuid.api.yangzihome.space" 
# 新的仅上传 UUID 的接口
UPLOAD_UUID_API_URL="https://encrypt.yangzihome.space/keygen_uuid.php" 

# 定义临时文件名称
PUBLIC_KEY_FILE="public.pem"
PRIVATE_KEY_FILE="private.pem"
PUBLIC_FROM_PRIVATE_FILE="public_from_private.pem" # 用于密钥验证的临时文件

# 定义一个文件来记录所有加密文件和其UUID的映射
README_FILE="encrypted_files_summary.txt"

# 函数：错误处理和退出 (用于脚本的致命错误)
function error_exit {
    local message="$1"
    echo "错误：$message" >&2 # 输出到标准错误
    # 对于致命错误，我们在这里清理，以防万一
    cleanup_temp_files # 调用清理临时文件，而不是 unset 变量
    exit 1
}

# 函数：清理临时密钥文件
function cleanup_temp_files {
    rm -f "$PUBLIC_KEY_FILE" "$PRIVATE_KEY_FILE" "$PUBLIC_FROM_PRIVATE_FILE" 2>/dev/null
    # 注意：这里不再 unset 变量，因为它们是局部于 encrypt_file 函数的
    # 并且如果脚本完全退出，它们自然会被销毁。
}

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo "警告：未找到 'jq' 命令。脚本将尝试使用 'sed' 进行JSON解析，但这可能不如 'jq' 健壮。" >&2
fi

# --- 核心加密函数 ---
# 将原有的加密逻辑封装成一个函数，以便循环调用
function encrypt_single_file {
    local INPUT_FILE="$1"
    local OUTPUT_FILE="${INPUT_FILE}.enc"

    echo "----------------------------------------------------"
    echo "正在处理文件: '$INPUT_FILE'"

    # 检查文件是否存在
    if [ ! -f "$INPUT_FILE" ]; then
        echo "警告：文件 '$INPUT_FILE' 不存在，跳过。"
        return 1 # 返回非零表示失败
    fi

    # 检查文件是否已经被加密过 (简单的检查 .enc 后缀)
    if [[ "$INPUT_FILE" == *.enc ]]; then
        echo "警告：文件 '$INPUT_FILE' 似乎已经是加密文件，跳过。"
        return 1
    fi

    # 每次加密一个文件前，先清理一下可能存在的临时文件，避免上次失败的影响
    cleanup_temp_files

    # 从统一API获取UUID和RSA密钥对 (POST请求)
    echo "正在从 $KEY_AND_UUID_API_URL 获取 UUID 和密钥对..."
    API_RESPONSE=$(curl -s -X POST "$KEY_AND_UUID_API_URL" \
      -H "Content-Type: application/json" \
      -d '{}') 

    # 检查API响应
    if [ -z "$API_RESPONSE" ]; then
        echo "错误：无法从API获取密钥对或UUID，API响应为空。跳过文件 '$INPUT_FILE'。" >&2
        return 1
    fi

    # 检查API响应是否包含错误状态
    if echo "$API_RESPONSE" | jq -e 'has("status") and .status == "error"' &> /dev/null; then
        ERROR_MESSAGE=$(echo "$API_RESPONSE" | jq -r '.message')
        echo "错误：API返回错误: $ERROR_MESSAGE (完整API响应: $API_RESPONSE)。跳过文件 '$INPUT_FILE'。" >&2
        return 1
    fi

    local PUBLIC_KEY_PEM
    local PRIVATE_KEY_PEM
    local UUID

    # 提取公钥、私钥和UUID (优先使用 jq，否则使用 sed)
    if command -v jq &> /dev/null; then
        PUBLIC_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.public_key_pem')
        PRIVATE_KEY_PEM=$(echo "$API_RESPONSE" | jq -r '.private_key_pem')
        UUID=$(echo "$API_RESPONSE" | jq -r '.uuid')
    else
        # 针对不包含 jq 的情况，使用 sed 进行粗略解析 (假设 key_pem 值为多行字符串，且 \n 已转义为 \\n)
        PUBLIC_KEY_PEM=$(echo "$API_RESPONSE" | sed -n 's/.*"public_key_pem":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
        PRIVATE_KEY_PEM=$(echo "$API_RESPONSE" | sed -n 's/.*"private_key_pem":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
        UUID=$(echo "$API_RESPONSE" | sed -n 's/.*"uuid":"\([^"]*\)".*/\1/p')
    fi

    # 检查提取结果
    if [ -z "$PUBLIC_KEY_PEM" ] || [ -z "$PRIVATE_KEY_PEM" ] || [ -z "$UUID" ]; then
        echo "错误：无法从API响应中提取公钥、私钥或UUID。API响应: $API_RESPONSE。跳过文件 '$INPUT_FILE'。" >&2
        return 1
    fi

    # 保存密钥到文件
    printf "%s" "$PUBLIC_KEY_PEM" > "$PUBLIC_KEY_FILE"
    printf "%s" "$PRIVATE_KEY_PEM" > "$PRIVATE_KEY_FILE"
    echo "RSA密钥对已成功获取并保存为 $PUBLIC_KEY_FILE 和 $PRIVATE_KEY_FILE。"

    # 验证API返回的公钥和私钥是否匹配
    echo "正在验证公钥和私钥匹配性..."
    openssl rsa -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_FROM_PRIVATE_FILE" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "警告：无法从私钥生成公钥进行匹配验证，可能是密钥格式问题或OpenSSL版本差异。跳过文件 '$INPUT_FILE'。" >&2
        cleanup_temp_files # 清理已生成的密钥文件
        return 1
    else
        # 移除PEM头尾进行比较，避免换行符差异
        local CLEAN_PUBLIC=$(awk 'NF { if($0 !~/^-/){print} }' "$PUBLIC_KEY_FILE")
        local CLEAN_PUBLIC_FROM_PRIVATE=$(awk 'NF { if($0 !~/^-/){print} }' "$PUBLIC_FROM_PRIVATE_FILE")

        if [ "$CLEAN_PUBLIC" != "$CLEAN_PUBLIC_FROM_PRIVATE" ]; then
            echo "错误：公钥和私钥不匹配！请检查API返回的密钥对。跳过文件 '$INPUT_FILE'。" >&2
            cleanup_temp_files
            return 1
        else
            echo "公钥和私钥匹配验证通过。"
        fi
    fi

    # --- 上传 UUID 的逻辑 ---
    echo "正在向 $UPLOAD_UUID_API_URL 上传 UUID..."
    local JSON_DATA
    if command -v jq &> /dev/null; then
        JSON_DATA=$(jq -n --arg uid "$UUID" '{uuid: $uid}')
    else
        JSON_DATA="{\"uuid\":\"$UUID\"}"
    fi

    local UPLOAD_RESPONSE=$(curl -s -X POST "$UPLOAD_UUID_API_URL" \
      -H "Content-Type: application/json" \
      -d "$JSON_DATA")

    # 检查UUID上传API响应
    if echo "$UPLOAD_RESPONSE" | grep -q '"status":"success"' || echo "$UPLOAD_RESPONSE" | grep -q '"status":"warning"'; then
      echo "UUID 上传成功或已存在。"
      echo "响应详情: $UPLOAD_RESPONSE"
    else
      echo "错误：UUID 上传API返回非成功或警告状态。请求数据: $JSON_DATA 响应详情: $UPLOAD_RESPONSE。跳过文件 '$INPUT_FILE'。" >&2
      cleanup_temp_files
      return 1
    fi

    echo "正在加密文件 '$INPUT_FILE'..."
    local AES_KEY
    local ENCRYPTED_DATA_BASE64
    local ENCRYPTED_KEY_BASE64

    # 1. 生成随机AES密钥 (Base64编码)
    AES_KEY=$(openssl rand -base64 32)

    # 2. 用AES加密文件内容，并将结果Base64编码
    ENCRYPTED_DATA_BASE64=$(openssl enc -aes-256-cbc -pbkdf2 -salt -in "$INPUT_FILE" -pass pass:"$AES_KEY" | openssl base64 -e -A)

    if [ $? -ne 0 ]; then
      echo "错误：文件AES加密失败。跳过文件 '$INPUT_FILE'。" >&2
      return 1
    fi

    # 3. 用RSA公钥加密AES密钥，并将结果Base64编码
    ENCRYPTED_KEY_BASE64=$(echo -n "$AES_KEY" | openssl pkeyutl -encrypt -pubin -inkey "$PUBLIC_KEY_FILE" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 | openssl base64 -e -A)

    if [ $? -ne 0 ]; then
      echo "错误：AES密钥RSA加密失败。请检查 $PUBLIC_KEY_FILE 是否有效，以及RSA填充模式是否正确。跳过文件 '$INPUT_FILE'。" >&2
      return 1
    fi

    # 4. 将所有部分按照特定格式写入输出文件
    echo "---BEGIN_AES_KEY---" > "$OUTPUT_FILE"
    echo "$ENCRYPTED_KEY_BASE64" >> "$OUTPUT_FILE"
    echo "---END_AES_KEY---" >> "$OUTPUT_FILE"
    echo "---BEGIN_ENCRYPTED_DATA---" >> "$OUTPUT_FILE"
    echo "$ENCRYPTED_DATA_BASE64" >> "$OUTPUT_FILE"
    echo "---END_ENCRYPTED_DATA---" >> "$OUTPUT_FILE"
    echo "---END_ENCRYPTED_FILE_AND_KEY---" >> "$OUTPUT_FILE"

    echo "文件已成功加密为 '$OUTPUT_FILE'"
    echo "关联的UUID: $UUID"

    # 将加密文件路径和UUID写入汇总文件
    echo "加密文件：$OUTPUT_FILE -> UUID: $UUID" >> "$README_FILE"

    # 清理本次加密的临时文件和密钥
    cleanup_temp_files

    echo "文件 '$INPUT_FILE' 加密完成！"
    return 0 # 返回零表示成功
}

# --- 主脚本逻辑 ---
if [ $# -eq 0 ]; then
    error_exit "请指定要加密的文件夹路径。用法: $0 <文件夹路径>"
fi

TARGET_DIR="$1"

# 检查目标是否是目录
if [ ! -d "$TARGET_DIR" ]; then
    error_exit "指定的路径 '$TARGET_DIR' 不是一个有效的目录。"
fi

echo "开始加密文件夹 '$TARGET_DIR' 中的所有 .txt 文件..."
echo "加密结果和UUID将记录在 '$README_FILE' 中。"
echo "----------------------------------------------------" >> "$README_FILE"
echo "加密任务开始于: $(date)" >> "$README_FILE"
echo "版本: $VERSION" >> "$README_FILE"
echo "----------------------------------------------------" >> "$README_FILE"

# 查找所有 .txt 文件并循环处理
# -type f: 只查找文件
# -name "*.txt": 查找所有以 .txt 结尾的文件
# -print0: 使用空字符作为分隔符，以处理文件名中的空格或特殊字符
# while IFS= read -r -d $'\0' file: 安全地读取以空字符分隔的文件名
find "$TARGET_DIR" -type f -name "*.txt" -print0 | while IFS= read -r -d $'\0' file; do
    encrypt_single_file "$file"
done

echo "----------------------------------------------------"
echo "所有 .txt 文件处理完毕。"
echo "加密结果摘要已保存到 '$README_FILE'。"
echo "加密任务完成于: $(date)" >> "$README_FILE"
echo "----------------------------------------------------" >> "$README_FILE"

exit 0
