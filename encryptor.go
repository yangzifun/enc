package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// API_URL 定义了获取密钥和UUID的API端点
const API_URL = "https://rsa-uuid.api.yangzifun.org"
const VERSION = "v3.1-go"

// APIResponse 结构体用于解析API返回的JSON数据
type APIResponse struct {
	PublicKeyPEM  string `json:"public_key_pem"`
	PrivateKeyPEM string `json:"private_key_pem"`
	UUID          string `json:"uuid"`
	Status        string `json:"status"`
	Message       string `json:"message"`
}

// printUsage 打印程序用法
func printUsage() {
	fmt.Println("RSA 密钥混合加密程序 - 版本:", VERSION)
	fmt.Println("-------------------------------------------")
	fmt.Println("错误：请指定要加密的文件路径")
	fmt.Printf("用法: %s <输入文件>\n", os.Args[0])
}

// logError 打印错误并退出
func logError(message string, err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "错误: %s\n详细信息: %v\n", message, err)
	} else {
		fmt.Fprintf(os.Stderr, "错误: %s\n", message)
	}
	os.Exit(1)
}

func main() {
	// 1. 检查输入参数
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}
	inputFile := os.Args[1]

	// 2. 检查文件是否存在
	if _, err := os.Stat(inputFile); os.IsNotExist(err) {
		logError(fmt.Sprintf("文件 '%s' 不存在", inputFile), nil)
	}

	fmt.Println("RSA 密钥混合加密程序 - 版本:", VERSION)
	fmt.Println("-------------------------------------------")

	// 3. 从API获取密钥和UUID
	fmt.Printf("正在从 %s 获取 UUID 和密钥对...\n", API_URL)
	apiRes, err := fetchKeysFromAPI()
	if err != nil {
		logError("无法从API获取密钥对", err)
	}

	// 4. 解析并验证密钥
	publicKey, err := parsePublicKey(apiRes.PublicKeyPEM)
	if err != nil {
		logError("解析公钥失败", err)
	}
	// 注意：私钥在此实现中未用于加密，仅为获取，但在实际解密流程中至关重要
	// 可以选择性地将 privateKeyPEM 保存起来，或直接在程序中验证其有效性

	// 5. 读取输入文件
	fmt.Printf("正在读取文件 '%s'...\n", inputFile)
	plaintext, err := os.ReadFile(inputFile)
	if err != nil {
		logError(fmt.Sprintf("读取文件 '%s' 失败", inputFile), err)
	}

	// 6. 执行混合加密
	fmt.Println("正在加密文件...")
	encryptedKeyBase64, encryptedDataBase64, err := hybridEncrypt(plaintext, publicKey)
	if err != nil {
		logError("混合加密失败", err)
	}

	// 7. 构造输出文件内容
	var outputContent strings.Builder
	outputContent.WriteString("---BEGIN_AES_KEY---\n")
	outputContent.WriteString(encryptedKeyBase64 + "\n")
	outputContent.WriteString("---END_AES_KEY---\n")
	outputContent.WriteString("---BEGIN_ENCRYPTED_DATA---\n")
	outputContent.WriteString(encryptedDataBase64 + "\n")
	outputContent.WriteString("---END_ENCRYPTED_DATA---\n")
	outputContent.WriteString("---END_ENCRYPTED_FILE_AND_KEY---\n")

	// 8. 写入输出文件
	outputFile := inputFile + ".enc"
	err = os.WriteFile(outputFile, []byte(outputContent.String()), 0644)
	if err != nil {
		logError(fmt.Sprintf("写入加密文件 '%s' 失败", outputFile), err)
	}

	fmt.Printf("文件已成功加密为 '%s'\n", outputFile)
	fmt.Printf("关联的UUID: %s\n", apiRes.UUID)

	// 9. 记录UUID到readme.txt
	logUUID(outputFile, apiRes.UUID)

	fmt.Println("加密完成！")
}

// fetchKeysFromAPI 从API获取密钥和UUID
func fetchKeysFromAPI() (*APIResponse, error) {
	resp, err := http.Post(API_URL, "application/json", bytes.NewBufferString("{}"))
	if err != nil {
		return nil, fmt.Errorf("API请求失败: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取API响应失败: %w", err)
	}

	var apiRes APIResponse
	if err := json.Unmarshal(body, &apiRes); err != nil {
		return nil, fmt.Errorf("解析API响应JSON失败: %w。原始响应: %s", err, string(body))
	}

	if apiRes.Status == "error" {
		return nil, fmt.Errorf("API返回错误: %s", apiRes.Message)
	}

	if apiRes.PublicKeyPEM == "" || apiRes.PrivateKeyPEM == "" || apiRes.UUID == "" {
		return nil, fmt.Errorf("API响应中缺少密钥或UUID。原始响应: %s", string(body))
	}

	fmt.Println("成功获取密钥对和UUID。")
	return &apiRes, nil
}

// parsePublicKey 从PEM格式的字符串中解析出RSA公钥
func parsePublicKey(publicKeyPEM string) (*rsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(publicKeyPEM))
	if block == nil {
		return nil, fmt.Errorf("无法解码PEM块")
	}
	pub, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("无法解析公钥: %w", err)
	}
	rsaPub, ok := pub.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("获取到的密钥不是RSA公钥")
	}
	return rsaPub, nil
}

// hybridEncrypt 执行混合加密
func hybridEncrypt(plaintext []byte, publicKey *rsa.PublicKey) (string, string, error) {
	// 1. 生成随机AES-256密钥
	aesKey := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, aesKey); err != nil {
		return "", "", fmt.Errorf("生成AES密钥失败: %w", err)
	}

	// 2. 使用AES-GCM加密数据。GCM是现代化的认证加密模式，比CBC更受推荐。
	block, err := aes.NewCipher(aesKey)
	if err != nil {
		return "", "", fmt.Errorf("创建AES cipher失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", "", fmt.Errorf("创建GCM模式失败: %w", err)
	}
	// GCM需要一个随机的nonce（数基），我们将其放在密文的前面
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", "", fmt.Errorf("生成nonce失败: %w", err)
	}
	// Seal函数会自动处理加密和认证，并将nonce作为第一个参数传入
	encryptedData := gcm.Seal(nonce, nonce, plaintext, nil)
	encryptedDataBase64 := base64.StdEncoding.EncodeToString(encryptedData)

	// 3. 使用RSA-OAEP加密AES密钥
	encryptedKey, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, publicKey, aesKey, nil)
	if err != nil {
		return "", "", fmt.Errorf("RSA加密AES密钥失败: %w", err)
	}
	encryptedKeyBase64 := base64.StdEncoding.EncodeToString(encryptedKey)

	return encryptedKeyBase64, encryptedDataBase64, nil
}

// logUUID 将UUID和文件名追加到readme.txt
func logUUID(filename, uuid string) {
	logMessage := fmt.Sprintf("加密的文件名称：%s : %s\n", filepath.Base(filename), uuid)

	f, err := os.OpenFile("readme.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "警告：无法写入日志到readme.txt: %v\n", err)
		return
	}
	defer f.Close()

	if _, err := f.WriteString(logMessage); err != nil {
		fmt.Fprintf(os.Stderr, "警告：写入日志到readme.txt失败: %v\n", err)
	}
}
