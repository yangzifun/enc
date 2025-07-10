适用场景：用于对敏感文件进行加密传输，通过非对称加密传输

> https://encrypt.yangzihome.space/


1、本系统用于加密和解密指定文件，使用前需阅读并遵守第六项内容；

2、执行脚本时将从接口`https://enc.api.yangzihome.space`获取UUID、RSA 密钥对；

3、执行后将上传UUID、RSA 密钥对到接口`https://enc.sunglowsec.com/keygen_uuid.php`；

请根据您的操作系统和具体需求，按照以下步骤操作：

#### **一、通用操作流程：**

1. **下载工具：** 根据您的操作系统（macOS, Linux, Windows），从“**下载脚本**”页面下载对应的加密/解密脚本或程序。
2. **加密文件：** 运行相应的加密工具，并指定您要加密的文件或目录。工具会生成一个唯一的**UUID**，请务必将其**妥善保存**。
3. **查询密钥：** 切换到本页面的“**密钥查询**”页面，输入您保存的UUID，查询与加密文件对应的私钥。私钥是解密文件的唯一凭证，**请务必将其下载并妥善保管，切勿泄露或丢失！**
4. **解密文件：** 运行相应的解密工具，并提供加密文件、以及您从“密钥查询”页面下载的私钥文件，即可解密文件。

#### **二、加密程序具体使用方法：**

##### **1. macOS / Linux Shell 脚本 (.sh) - 单文件加密**

这些脚本通常需要您的系统安装了 `curl`, `jq` (用于JSON解析), `openssl` 等命令工具。请确保这些工具已安装。

1. **赋予执行权限：** 打开终端，导航到脚本所在目录，执行以下命令：

   ```
   chmod +x encrypt_linux.sh
   ```

   ```
   chmod +x encrypt_osx.sh
   ```

2. **执行加密：** 在终端中运行脚本，后面跟上要加密的文件路径：

   ```
   ./encrypt_linux.sh /path/to/your/file.txt
   ```

   ```
   ./encrypt_osx.sh /path/to/your/file.txt
   ```

   这会将 `file.txt` 加密为 `file.txt.enc`，并在控制台显示生成的UUID。**请务必记录此UUID。**

##### **2. Windows 程序 (.exe) - 单文件加密**

这是一个独立的可执行文件，通常无需额外环境依赖。

1. **执行加密：** 打开命令提示符（CMD）或 PowerShell，导航到 `.exe` 程序所在目录，然后运行：

   ```
   encryptor.exe C:\path\to\your\file.txt
   ```

   这会将 `file.txt` 加密为 `file.txt.enc`，并在控制台显示生成的UUID。**请务必记录此UUID。**

##### **3. Python 程序 (.py) - 单文件加密**

您需要确保系统已安装 Python 3 运行环境。如果缺少必要的 Python 库，例如 `requests` 或 `pycryptodome`，您可能需要通过 pip 安装：`pip install requests pycryptodome`。

1. **运行环境准备：** 确保已安装 Python 3 及所需库。

2. **执行加密：** 打开终端或命令提示符，导航到 `.py` 程序所在目录，然后运行：

   ```
   python encryptor.py /path/to/your/file.txt
   ```

   这会将 `file.txt` 加密为 `file.txt.enc`，并在控制台显示生成的UUID。**请务必记录此UUID。**

#### **三、批量加密程序具体使用方法：**

批量加密脚本/程序会遍历指定目录下的文件进行加密。请注意，每个被加密的文件都会生成一个独立的UUID。

##### **1. macOS / Linux Shell 脚本 (.sh) - 批量加密**

这些脚本通常需要与单文件加密脚本（如 `encrypt_linux.sh` 或 `encrypt_osx.sh`）放在同一目录下，因为它们会调用这些脚本来执行实际的加密操作。

1. **赋予执行权限：**

   ```
   chmod +x batch_encrypt_linux.sh
   chmod +x encrypt_linux.sh
                               
   ```

   ```
   chmod +x batch_encrypt_osx.sh
   chmod +x encrypt_osx.sh
                               
   ```

2. **执行批量加密：** 在终端中运行。您可以选择指定要加密的目录路径：

   ```
   ./batch_encrypt_linux.sh [可选：要加密的目录路径]
   ```

   ```
   ./batch_encrypt_osx.sh [可选：要加密的目录路径]
   ```

   如果不指定目录路径，脚本会加密当前目录中预设文件类型（请查看脚本内容了解支持的文件类型）。

##### **2. Windows 程序 (.ps1) - 批量加密 (PowerShell 脚本)**

PowerShell 脚本可能需要调整 PowerShell 的执行策略 (Execution Policy) 才能运行。这些脚本通常需要与单文件加密程序（如 `encryptor.exe`）放在同一目录下。如遇编码错误，请将 `.ps1` 脚本保存为 `UTF-8 (带 BOM)` 编码。

1. **调整执行策略（如果需要）：** 在 PowerShell 中执行：

   ```
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

   此操作允许您运行本地创建的脚本和来自互联网的已签名脚本。完成后可考虑恢复策略：`Set-ExecutionPolicy Restricted -Scope CurrentUser`。

2. **执行批量加密：** 打开 PowerShell，导航到 `.ps1` 脚本所在目录，然后运行：

   ```
   .\batch_encryptor.ps1  -FileExtensions @("txt", "jpg", "docx")
   ```

   此命令将加密指定目录下所有 `.txt`、`.jpg` 和 `.docx` 文件。

#### **四、指定目录加密：**

这些脚本/程序旨在递归地加密指定目录及其子目录下的所有文件。

##### **1. macOS / Linux Shell 脚本 (.sh) - 目录加密**

1. **赋予执行权限：**

   ```
   chmod +x encrypt_folder_linux.sh
   ```

   ```
   chmod +x encrypt_folder_osx.sh
   ```

2. **执行目录加密：** 在终端中运行，指定要加密的目录路径：

   ```
   ./encrypt_folder_linux.sh /path/to/your/folder
   ```

   ```
   ./encrypt_folder_osx.sh /path/to/your/folder
   ```

   脚本会遍历指定文件夹及其所有子文件夹，找到所有 .txt 文件，并对它们进行单独加密。每个加密后的文件都会生成一个新的 UUID 和密钥对（密钥对不上传），并在 `encrypted_files_summary.txt` 中记录文件路径和对应的 UUID。

##### **2. Windows 程序 (.exe) - 目录加密**

1. **执行目录加密：** 打开命令提示符（CMD）或 PowerShell，导航到 `.exe` 程序所在目录，然后运行：

   ```
   encryptor_folder.exe C:\path\to\your\folder
   ```

   程序会遍历指定目录及其子目录下的文件进行加密。

##### **3. Python 程序 (.py) - 目录加密**

1. **运行环境准备：** 确保已安装 Python 3 和必要的库（例如：`pycryptodome`）。

2. **执行加密：** 打开终端或命令提示符，导航到 `.py` 程序所在目录，然后运行：

   ```
   python encryptor_folder.py /path/to/your/folder
   ```

   程序会遍历指定目录及其子目录下的文件进行加密。

#### **五、解密程序使用方法：**

解密过程需要加密时生成的加密文件（通常以 `.enc` 结尾）以及从本网站查询并下载的私钥文件（`.pem`）。

##### **1. macOS / Linux Shell 脚本 (.sh) - 解密**

1. **赋予执行权限：** 打开终端，导航到脚本所在目录，执行：

   ```
   chmod +x decrypt_linux.sh
   ```

   ```
   chmod +x decrypt_osx.sh
   ```

2. **执行解密：** 在终端中运行，提供私钥文件路径和加密文件路径：

   ```
   ./decrypt_linux.sh /path/to/your/private_key_xxxx.pem /path/to/your/file.txt.enc
   ```

   ```
   ./decrypt_osx.sh /path/to/your/private_key_xxxx.pem /path/to/your/file.txt.enc
   ```

   这会将 `file.txt.enc` 解密为 `file.txt`（或原始文件名）。请确保私钥文件和加密文件路径正确。

##### **2. Windows 程序 (.exe) - 解密**

1. **执行解密：** 打开命令提示符（CMD）或 PowerShell，导航到 `.exe` 程序所在目录，然后运行：

   ```
   decryptor.exe C:\path\to\your\private_key_xxxx.pem C:\path\to\your\file.txt.enc
   ```

   这会将 `file.txt.enc` 解密为原始文件。请确保私钥文件和加密文件路径正确。

##### **3. Python 程序 (.py) - 解密**

1. **运行环境准备：** 确保已安装 Python 3 和必要的库（例如：`pycryptodome`）。

2. **执行解密：** 打开终端或命令提示符，导航到 `.py` 程序所在目录，然后运行：

   ```
   python decryptor.py /path/to/your/private_key_xxxx.pem /path/to/your/file.txt.enc
   ```

   这会将 `file.txt.enc` 解密为原始文件。请确保私钥文件和加密文件路径正确。

#### **六、重要注意事项：**

- **UUID 和 私钥：** UUID是识别密钥的唯一凭证，而私钥是解密文件的唯一密钥。 **务必妥善保存UUID和下载的私钥文件，并确保私钥的私密性！** 丢失私钥将导致文件永远无法解密。
- **网络连接：** 加密过程需要通过网络连接到加密服务器获取RSA密钥对和上传UUID与密钥。请确保您的计算机有稳定的网络连接。
- **API 限制：** 本系统依赖外部API服务，请注意API的可用性和潜在的使用限制；脚本、程序及API服务会不定时更新，如遇执行错误问题，请从该网站更新程序。
- **数据保存：** 本系统将定期清理数据库，如已使用加密软件，请尽快下载密钥。
- **加密与解密环境：** 建议在与加密时相同的操作系统或类似的运行环境下进行解密，以避免潜在的兼容性问题。
- **密钥备用接口：** 如执行脚本时文件已加密，但密钥对未正常上传，请使用备用接口查询密钥对：`https://uuidgetkey.api.yangzihome.space/`
- **重要声明：** **该站点提供的脚本仅用于演练防加密勒索，其他用途及使用过程中数据丢失，与本服务无关！** 加密过程中，源文件不会被自动清除。如您需要清除源文件，请自行修改脚本以包含文件删除操作。