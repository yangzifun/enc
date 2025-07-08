<#
.SYNOPSIS
    批量执行指定的加密程序对当前目录下指定格式的文件进行加密。

.DESCRIPTION
    此脚本会查找当前目录下所有符合指定文件扩展名的文件，
    然后逐一调用您的加密程序（例如 encryptor.exe 或您实际打包的程序）对它们进行加密。
    请确保加密程序在脚本执行的相同目录下或已添加到系统PATH。

.PARAMETER EncryptorProgramName
    要执行的加密程序的名称（例如 "encryptor.exe" 或 "decryptor.exe"）。
    默认为 "encryptor.exe"。请根据您实际打包的EXE文件名进行调整。

.PARAMETER FileExtensions
    一个字符串数组，包含需要加密的文件扩展名（例如：@("txt", "docx", "pdf")）。

.EXAMPLE
    # 假设您的加密程序是 encryptor.exe，加密所有 .txt 和 .docx 文件
    .\batch_encryptor.ps1 -FileExtensions @("txt", "docx")

.EXAMPLE
    # 如果您的加密程序确实叫做 decryptor.exe (但执行的是加密功能)，加密所有 .xlsx 和 .csv 文件
    .\batch_encryptor.ps1 -EncryptorProgramName "decryptor.exe" -FileExtensions @("xlsx", "csv")
#>

param(
    [Parameter(Mandatory=$false)] # 设为非强制，提供默认值
    [string]$EncryptorProgramName = "encryptor.exe", # 默认使用 "encryptor.exe"

    [Parameter(Mandatory=$true)]
    [string[]]$FileExtensions
)

# 获取当前脚本的目录
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 构建加密程序的完整路径
$encryptorPath = Join-Path -Path $scriptDir -ChildPath $EncryptorProgramName

# 检查加密程序是否存在
if (-not (Test-Path $encryptorPath)) {
    Write-Error "错误：找不到加密程序 '$EncryptorProgramName'。请确保它位于脚本相同的目录下，或者通过 -EncryptorProgramName 参数指定正确的名称。"
    exit 1
}

Write-Host "--------------------------------------------------------"
Write-Host "开始批量加密文件..."
Write-Host "使用的加密程序: $encryptorPath"
Write-Host "将加密的文件扩展名: $($FileExtensions -join ', ')"
Write-Host "--------------------------------------------------------"

# 遍历当前目录下的所有文件
foreach ($ext in $FileExtensions) {
    # 确保扩展名不包含点，Get-ChildItem -Filter 自动处理
    $cleanExt = $ext.TrimStart('.') 
    Get-ChildItem -Path $scriptDir -File -Filter "*.$cleanExt" | ForEach-Object {
        $filePath = $_.FullName
        $fileName = $_.Name

        # 检查文件是否已经被加密过（通过检查是否存在 .enc 扩展名）
        # 如果文件本身就是 .enc 结尾，则跳过，避免处理已经加密的文件
        if ($fileName.EndsWith(".enc", [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "跳过 '$fileName' - 似乎已经被加密过 (.enc 扩展名)。" -ForegroundColor Yellow
            return # 使用 return 跳过当前 Foreach-Object 的迭代
        }

        # 检查是否已经存在同名的 .enc 文件，避免重复加密
        $encryptedFilePath = "$filePath.enc"
        if (Test-Path $encryptedFilePath) {
            Write-Host "跳过 '$fileName' - 已存在加密文件 '$($encryptedFilePath | Split-Path -Leaf)'. " -ForegroundColor Yellow
            return # 使用 return 跳过当前 Foreach-Object 的迭代
        }

        Write-Host "正在加密文件: '$fileName'..." -ForegroundColor Green
        
        try {
            # 执行加密程序，并将文件路径作为参数传递
            # 使用 Start-Process -Wait 等待程序完成，避免并行运行过多实例
            # 注意：对于 --console 打包的EXE，-NoNewWindow 可能无法阻止控制台窗口的弹出。
            # 如果您需要完全静默，请使用 pyinstaller --noconsole 重新打包EXE。
            Start-Process -FilePath $encryptorPath -ArgumentList "`"$filePath`"" -NoNewWindow -Wait -ErrorAction Stop

            Write-Host "成功加密 '$fileName'." -ForegroundColor Green
        }
        catch {
            Write-Error "加密文件 '$fileName' 失败: $($_.Exception.Message)"
        }
    }
}

Write-Host "--------------------------------------------------------"
Write-Host "批量加密完成！"
Write-Host "--------------------------------------------------------"
