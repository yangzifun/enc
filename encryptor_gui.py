import sys
import os
import requests
import json
import base64
import threading
import tkinter as tk
from tkinter import filedialog, messagebox
from tkinterdnd2 import DND_FILES, TkinterDnD
import datetime

# 引入原有加密模块
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# --- 原有的核心加密逻辑 ---

VERSION = "v4.2-GUI"  # [MODIFIED] 版本号递增
API_ENDPOINT = "https://rsa-uuid.api.yangzihome.space"
OPENSSL_SALTED_MAGIC = b'Salted__'
PBKDF2_ITERATIONS = 10000


class EncryptorApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"文件加密工具 {VERSION}")
        # [MODIFIED] 增加窗口高度以容纳新的UUID标签
        self.root.geometry("500x380")
        self.root.resizable(False, False)

        # --- UI 组件定义 ---

        self.drop_target_frame = tk.Frame(root, relief="sunken", borderwidth=2)
        self.drop_target_frame.pack(pady=20, padx=20, fill="x", expand=True)

        self.drop_label = tk.Label(
            self.drop_target_frame,
            text="\n\n将文件拖拽到此处\n\n",
            font=("Arial", 14),
            fg="grey"
        )
        self.drop_label.pack(pady=20)

        self.select_button = tk.Button(
            root,
            text="或点击选择文件",
            font=("Arial", 12),
            command=self.select_file
        )
        self.select_button.pack(pady=(0, 20))

        self.status_label = tk.Label(
            root,
            text="请选择一个文件进行加密",
            font=("Arial", 10),
            fg="blue",
            wraplength=480
        )
        self.status_label.pack(pady=(5, 10), padx=20)

        # --- [NEW] 新增用于显示UUID的标签 ---
        self.uuid_label = tk.Label(
            root,
            text="UUID 将在此处显示",
            font=("Consolas", 11),  # 使用等宽字体，显示UUID更好看
            fg="navy",
            wraplength=480
        )
        self.uuid_label.pack(pady=(5, 15), padx=20)

        # --- 绑定拖拽事件 ---
        self.drop_target_frame.drop_target_register(DND_FILES)
        self.drop_label.drop_target_register(DND_FILES)

        self.drop_target_frame.dnd_bind('<<Drop>>', self.handle_drop)
        self.drop_label.dnd_bind('<<Drop>>', self.handle_drop)

    def update_status(self, message, color="black"):
        self.status_label.config(text=message, fg=color)
        self.root.update_idletasks()

    # --- [NEW] 新增一个专门更新UUID标签的方法 ---
    def update_uuid_display(self, new_uuid=""):
        """更新专门显示UUID的标签，如果为空则显示占位符"""
        if new_uuid:
            self.uuid_label.config(text=f"UUID: {new_uuid}")
        else:
            self.uuid_label.config(text="UUID 将在此处显示")
        self.root.update_idletasks()

    def set_ui_busy(self, is_busy):
        state = "disabled" if is_busy else "normal"
        self.select_button.config(state=state)
        if is_busy:
            self.drop_target_frame.drop_target_unregister()
            self.drop_label.drop_target_unregister()
            self.update_status("正在处理，请稍候...", "orange")
        else:
            self.drop_target_frame.drop_target_register(DND_FILES)
            self.drop_label.drop_target_register(DND_FILES)

    def select_file(self):
        filepath = filedialog.askopenfilename()
        if filepath:
            self.start_encryption_thread(filepath)

    def handle_drop(self, event):
        filepath = event.data.strip()
        if filepath.startswith('{') and filepath.endswith('}'):
            filepath = filepath[1:-1]

        if os.path.isfile(filepath):
            self.start_encryption_thread(filepath)
        else:
            self.update_status(f"错误: 拖入的路径不是一个有效文件。\n'{filepath}'", "red")

    def start_encryption_thread(self, filepath):
        # [MODIFIED] 在开始新任务时，清空上一次的UUID显示
        self.update_uuid_display()
        self.set_ui_busy(True)
        thread = threading.Thread(target=self.run_encryption_process, args=(filepath,))
        thread.daemon = True
        thread.start()

    def run_encryption_process(self, input_file_path):
        try:
            absolute_input_path = os.path.abspath(input_file_path)
            output_file_path = f"{absolute_input_path}.enc"

            # 步骤 1: 获取UUID和密钥
            self.update_status("步骤 1/5: 正在从API获取UUID和RSA密钥对...", "orange")
            generated_uuid, public_key_pem, _ = self._get_uuid_and_keys()

            # ... (后续步骤基本不变) ...
            public_key = serialization.load_pem_public_key(public_key_pem.encode('utf-8'), backend=default_backend())

            self.update_status(f"步骤 2/5: 正在读取文件 '{os.path.basename(absolute_input_path)}'...", "orange")
            with open(absolute_input_path, 'rb') as f:
                file_content = f.read()

            self.update_status("步骤 3/5: 正在使用AES加密文件...", "orange")
            raw_aes_key_bytes = os.urandom(32)
            aes_password_b64_str = base64.b64encode(raw_aes_key_bytes).decode('utf-8').rstrip('=')
            encrypted_file_content_with_salt = self._encrypt_data_aes(file_content, aes_password_b64_str)
            encrypted_data_base64 = base64.b64encode(encrypted_file_content_with_salt).decode('utf-8')

            self.update_status("步骤 4/5: 正在使用RSA加密AES密钥...", "orange")
            encrypted_aes_key_bytes = public_key.encrypt(
                aes_password_b64_str.encode('utf-8'),
                padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None)
            )
            encrypted_key_base64 = base64.b64encode(encrypted_aes_key_bytes).decode('utf-8')

            self.update_status(f"步骤 5/5: 正在写入加密文件 '{os.path.basename(output_file_path)}'...", "orange")
            with open(output_file_path, 'w') as f:
                f.write("---BEGIN_AES_KEY---\n")
                f.write(encrypted_key_base64 + "\n")
                f.write("---END_AES_KEY---\n")
                f.write("---BEGIN_ENCRYPTED_DATA---\n")
                f.write(encrypted_data_base64 + "\n")
                f.write("---END_ENCRYPTED_DATA---\n")
                f.write("---END_ENCRYPTED_FILE_AND_KEY---\n")

            # 静默记录到log.txt
            log_file_path = "log.txt"
            with open(log_file_path, 'a', encoding='utf-8') as f:
                timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                log_entry = f"[{timestamp}] | File: {output_file_path} | UUID: {generated_uuid}\n"
                f.write(log_entry)

            # --- [MODIFIED] 更新成功提示和UI显示 ---
            # 1. 在主状态栏显示成功
            success_status = f"加密成功! 文件已保存为: '{os.path.basename(output_file_path)}'"
            self.update_status(success_status, "green")
            # 2. 在专门的标签中显示UUID
            self.update_uuid_display(generated_uuid)
            # 3. 弹窗提示，不提及日志文件
            messagebox.showinfo("成功", f"文件加密成功！\n\n输出文件: {output_file_path}")

        except Exception as e:
            error_message = f"加密过程中发生错误:\n{e}"
            self.update_status(error_message, "red")
            # [MODIFIED] 错误发生时也清空UUID显示
            self.update_uuid_display()
            messagebox.showerror("错误", error_message)

        finally:
            self.set_ui_busy(False)
            # 成功后，状态栏会显示成功信息，UUID会显示ID，几秒后可以重置提示
            self.root.after(5000, lambda: self.update_status("请选择或拖拽下一个文件进行加密", "blue"))

    # --- 后面的方法保持不变 ---

    def _encrypt_data_aes(self, data, aes_password_str):
        salt = os.urandom(16)
        kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32 + 16, salt=salt, iterations=PBKDF2_ITERATIONS,
                         backend=default_backend())
        derived_key_iv = kdf.derive(aes_password_str.encode('utf-8'))
        return OPENSSL_SALTED_MAGIC + salt + Cipher(algorithms.AES(derived_key_iv[:32]), modes.CBC(derived_key_iv[32:]),
                                                    backend=default_backend()).encryptor().update(
            data + bytes([16 - len(data) % 16]) * (16 - len(data) % 16)))

        def _get_uuid_and_keys(self):
            try:
                response = requests.post(API_ENDPOINT, json={}, timeout=15)
                response.raise_for_status()
                data = response.json()
                generated_uuid, public_key_pem, private_key_pem = data.get('uuid'), data.get(
                    'public_key_pem'), data.get('private_key_pem')

                if not all([generated_uuid, public_key_pem, private_key_pem]):
                    raise ValueError(f"API返回数据不完整。响应: {response.text}")

                # Key validation logic here...

                return generated_uuid, public_key_pem, private_key_pem

            except requests.exceptions.RequestException as e:
                raise RuntimeError(f"网络请求失败: {e}")
            except (json.JSONDecodeError, ValueError) as e:
                raise RuntimeError(f"API响应处理失败: {e}")

    if __name__ == "__main__":
        root = TkinterDnD.Tk()
        app = EncryptorApp(root)
        root.mainloop()
