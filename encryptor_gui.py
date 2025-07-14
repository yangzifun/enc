import os
import requests
import json
import base64
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinterdnd2 import DND_FILES, TkinterDnD
import datetime

# 引入核心加密/解密库
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# --- 全局常量 ---

VERSION = "v5.0"  # [MODIFIED] 主版本更新，代表重大功能增加
API_ENDPOINT = "https://rsa-uuid.api.yangzihome.space"
OPENSSL_SALTED_MAGIC = b'Salted__'
PBKDF2_ITERATIONS = 10000


class CryptoApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"文件加解密工具 {VERSION}")
        self.root.geometry("550x450")  # 调整窗口大小
        self.root.resizable(False, False)

        # --- 用于解密的状态变量 ---
        self.encrypted_file_path = tk.StringVar()
        self.private_key_path = tk.StringVar()

        # --- 创建选项卡控制器 ---
        self.notebook = ttk.Notebook(root)
        self.notebook.pack(expand=True, fill="both", padx=10, pady=10)

        # --- 创建并添加选项卡 ---
        self.encrypt_tab = ttk.Frame(self.notebook, padding="10")
        self.decrypt_tab = ttk.Frame(self.notebook, padding="10")

        self.notebook.add(self.encrypt_tab, text="加密 (Encrypt)")
        self.notebook.add(self.decrypt_tab, text="解密 (Decrypt)")

        # --- 初始化每个选项卡的内容 ---
        self.create_encrypt_widgets()
        self.create_decrypt_widgets()

    # =====================================================================
    # 1. 加密功能相关UI和逻辑
    # =====================================================================
    def create_encrypt_widgets(self):
        # 拖拽区域
        drop_target_frame = tk.Frame(self.encrypt_tab, relief="sunken", borderwidth=2)
        drop_target_frame.pack(pady=10, padx=10, fill="x", expand=True)

        drop_label = tk.Label(drop_target_frame, text="\n将文件拖拽到此处进行加密\n", font=("Arial", 14), fg="grey")
        drop_label.pack(pady=20)

        # 按钮和标签
        select_button = tk.Button(self.encrypt_tab, text="或点击选择加密文件", font=("Arial", 12),
                                  command=self.select_file_to_encrypt)
        select_button.pack(pady=(0, 10))

        self.status_label_encrypt = tk.Label(self.encrypt_tab, text="请选择一个文件进行加密", font=("Arial", 10),
                                             fg="blue", wraplength=480)
        self.status_label_encrypt.pack(pady=(5, 5), padx=10)

        self.uuid_label = tk.Label(self.encrypt_tab, text="UUID 将在此处显示", font=("Consolas", 11), fg="navy",
                                   wraplength=480)
        self.uuid_label.pack(pady=(5, 5), padx=10)

        # 绑定拖拽
        drop_target_frame.drop_target_register(DND_FILES)
        drop_label.drop_target_register(DND_FILES)
        drop_target_frame.dnd_bind('<<Drop>>', self.handle_drop_to_encrypt)
        drop_label.dnd_bind('<<Drop>>', self.handle_drop_to_encrypt)

        # 绑定引用以便之后禁用
        self.encrypt_widgets = [select_button, drop_target_frame]

    def select_file_to_encrypt(self):
        filepath = filedialog.askopenfilename()
        if filepath:
            self.start_encryption_thread(filepath)

    def handle_drop_to_encrypt(self, event):
        filepath = event.data.strip('{}')
        if os.path.isfile(filepath):
            self.start_encryption_thread(filepath)
        else:
            self.update_status(f"错误: 拖入的不是有效文件: '{filepath}'", "red")

    def start_encryption_thread(self, filepath):
        self.update_uuid_display()
        self.set_encrypt_ui_busy(True)
        thread = threading.Thread(target=self._run_encryption_process, args=(filepath,), daemon=True)
        thread.start()

    def set_encrypt_ui_busy(self, is_busy):
        state = "disabled" if is_busy else "normal"
        for widget in self.encrypt_widgets:
            if isinstance(widget, tk.Button):
                widget.config(state=state)

        if is_busy:
            self.update_status("正在处理，请稍候...", "orange")
        # re-enable dnd is handled inside start thread. here just disable

    def update_status(self, message, color="black"):
        self.status_label_encrypt.config(text=message, fg=color)
        self.root.update_idletasks()

    def update_uuid_display(self, new_uuid=""):
        self.uuid_label.config(text=f"UUID: {new_uuid}" if new_uuid else "UUID 将在此处显示")
        self.root.update_idletasks()

    def _run_encryption_process(self, input_file_path):
        # ... (加密逻辑与之前版本基本一致) ...
        try:
            absolute_input_path = os.path.abspath(input_file_path)
            output_file_path = f"{absolute_input_path}.enc"
            self.update_status("步骤 1/5: 获取密钥...", "orange")
            generated_uuid, public_key_pem, _ = self._get_uuid_and_keys()
            public_key = serialization.load_pem_public_key(public_key_pem.encode('utf-8'), backend=default_backend())

            self.update_status(f"步骤 2/5: 读取文件...", "orange")
            with open(absolute_input_path, 'rb') as f:
                file_content = f.read()

            self.update_status("步骤 3/5: AES加密...", "orange")
            raw_aes_key_bytes = os.urandom(32)
            aes_password_b64_str = base64.b64encode(raw_aes_key_bytes).decode('utf-8').rstrip('=')
            encrypted_file_content_with_salt = self._encrypt_data_aes(file_content, aes_password_b64_str)
            encrypted_data_base64 = base64.b64encode(encrypted_file_content_with_salt).decode('utf-8')

            self.update_status("步骤 4/5: RSA加密密钥...", "orange")
            encrypted_key_base64 = base64.b64encode(public_key.encrypt(aes_password_b64_str.encode('utf-8'),
                                                                       padding.OAEP(
                                                                           mgf=padding.MGF1(algorithm=hashes.SHA256()),
                                                                           algorithm=hashes.SHA256(),
                                                                           label=None))).decode('utf-8')

            self.update_status(f"步骤 5/5: 写入文件...", "orange")
            with open(output_file_path, 'w') as f:
                f.write(f"---BEGIN_AES_KEY---\n{encrypted_key_base64}\n---END_AES_KEY---\n"
                        f"---BEGIN_ENCRYPTED_DATA---\n{encrypted_data_base64}\n---END_ENCRYPTED_DATA---\n"
                        f"---END_ENCRYPTED_FILE_AND_KEY---\n")

            with open("log.txt", 'a', encoding='utf-8') as f:
                f.write(
                    f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ENCRYPT | File: {output_file_path} | UUID: {generated_uuid}\n")

            success_status = f"加密成功! 文件已保存为: '{os.path.basename(output_file_path)}'"
            self.update_status(success_status, "green")
            self.update_uuid_display(generated_uuid)
            messagebox.showinfo("成功", f"文件加密成功！\n\n输出文件: {output_file_path}")
        except Exception as e:
            self.update_status(f"加密错误: {e}", "red")
            self.update_uuid_display()
            messagebox.showerror("错误", f"加密过程中发生错误:\n{e}")
        finally:
            self.set_encrypt_ui_busy(False)
            self.root.after(5000, lambda: self.update_status("请选择或拖拽下一个文件进行加密", "blue"))

    def _encrypt_data_aes(self, data, aes_password_str):
        salt = os.urandom(16)
        kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32 + 16, salt=salt, iterations=PBKDF2_ITERATIONS,
                         backend=default_backend())
        derived_key_iv = kdf.derive(aes_password_str.encode('utf-8'))
        pad_len = 16 - (len(data) % 16)
        padded_data = data + bytes([pad_len]) * pad_len
        cipher = Cipher(algorithms.AES(derived_key_iv[:32]), modes.CBC(derived_key_iv[32:]), backend=default_backend())
        return OPENSSL_SALTED_MAGIC + salt + (cipher.encryptor().update(padded_data) + cipher.encryptor().finalize())

    def _get_uuid_and_keys(self):
        try:
            response = requests.post(API_ENDPOINT, json={}, timeout=15)
            response.raise_for_status()
            data = response.json()
            if not all(k in data for k in ['uuid', 'public_key_pem', 'private_key_pem']):
                raise ValueError("API响应数据不完整")
            return data['uuid'], data['public_key_pem'], data['private_key_pem']
        except Exception as e:
            raise RuntimeError(f"网络或API错误: {e}")

    # =====================================================================
    # 2. 解密功能相关UI和逻辑
    # =====================================================================
    def create_decrypt_widgets(self):
        # 选择加密文件
        tk.Label(self.decrypt_tab, text="1. 选择加密文件 (.enc):").pack(anchor="w", pady=(10, 0))
        frame_enc = tk.Frame(self.decrypt_tab)
        frame_enc.pack(fill="x")
        tk.Entry(frame_enc, textvariable=self.encrypted_file_path, state="readonly").pack(side="left", expand=True,
                                                                                          fill="x", padx=(0, 5))
        tk.Button(frame_enc, text="选择...", command=self.select_encrypted_file).pack(side="right")

        # 选择私钥文件
        tk.Label(self.decrypt_tab, text="2. 选择私钥文件 (.pem, .key, etc.):").pack(anchor="w", pady=(20, 0))
        frame_key = tk.Frame(self.decrypt_tab)
        frame_key.pack(fill="x")
        tk.Entry(frame_key, textvariable=self.private_key_path, state="readonly").pack(side="left", expand=True,
                                                                                       fill="x", padx=(0, 5))
        tk.Button(frame_key, text="选择...", command=self.select_private_key).pack(side="right")

        # 解密按钮
        self.decrypt_button = tk.Button(self.decrypt_tab, text="开始解密", font=("Arial", 14),
                                        command=self.start_decryption_thread)
        self.decrypt_button.pack(side="bottom", pady=20, fill="x")

        # 状态标签
        self.status_label_decrypt = tk.Label(self.decrypt_tab, text="请选择加密文件和私钥", font=("Arial", 10),
                                             fg="blue", wraplength=480)
        self.status_label_decrypt.pack(side="bottom", pady=10)

    def select_encrypted_file(self):
        path = filedialog.askopenfilename(title="选择加密文件",
                                          filetypes=[("Encrypted files", "*.enc"), ("All files", "*.*")])
        if path: self.encrypted_file_path.set(path)

    def select_private_key(self):
        path = filedialog.askopenfilename(title="选择私钥文件",
                                          filetypes=[("PEM files", "*.pem"), ("Key files", "*.key"),
                                                     ("All files", "*.*")])
        if path: self.private_key_path.set(path)

    def update_decrypt_status(self, message, color="black"):
        self.status_label_decrypt.config(text=message, fg=color)
        self.root.update_idletasks()

    def start_decryption_thread(self):
        enc_path = self.encrypted_file_path.get()
        key_path = self.private_key_path.get()
        if not enc_path or not key_path:
            messagebox.showwarning("输入不完整", "请同时选择加密文件和私钥文件。")
            return

        self.decrypt_button.config(state="disabled")
        self.update_decrypt_status("开始解密...", "orange")
        thread = threading.Thread(target=self._run_decryption_process, args=(key_path, enc_path), daemon=True)
        thread.start()

    def _run_decryption_process(self, private_key_path, input_file_path):
        try:
            # 1. 读取私钥
            self.update_decrypt_status("步骤 1/4: 加载私钥...", "orange")
            if not os.path.exists(private_key_path): raise FileNotFoundError(f"私钥文件不存在: {private_key_path}")
            with open(private_key_path, 'rb') as key_file:
                private_key = serialization.load_pem_private_key(key_file.read(), password=None,
                                                                 backend=default_backend())

            # 2. 解析加密文件
            self.update_decrypt_status("步骤 2/4: 解析加密文件...", "orange")
            if not os.path.exists(input_file_path): raise FileNotFoundError(f"加密文件不存在: {input_file_path}")
            with open(input_file_path, 'r') as f:
                content = f.read()

            parts = {}
            current_section = None
            for line in content.splitlines():
                if line == "---BEGIN_AES_KEY---":
                    current_section = "AES_KEY"; parts["AES_KEY"] = []
                elif line == "---END_AES_KEY---":
                    current_section = None
                elif line == "---BEGIN_ENCRYPTED_DATA---":
                    current_section = "ENCRYPTED_DATA"; parts["ENCRYPTED_DATA"] = []
                elif line == "---END_ENCRYPTED_DATA---":
                    current_section = None
                elif current_section:
                    parts[current_section].append(line.strip())

            encrypted_key_base64 = "".join(parts.get("AES_KEY", []))
            encrypted_data_base64 = "".join(parts.get("ENCRYPTED_DATA", []))
            if not encrypted_key_base64 or not encrypted_data_base64: raise ValueError("加密文件格式不正确")

            # 3. RSA 解密 AES 密钥
            self.update_decrypt_status("步骤 3/4: RSA解密AES密钥...", "orange")
            encrypted_aes_key_bytes = base64.b64decode(encrypted_key_base64)
            decrypted_aes_password_bytes = private_key.decrypt(encrypted_aes_key_bytes,
                                                               padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),
                                                                            algorithm=hashes.SHA256(), label=None))
            aes_password_b64_str = decrypted_aes_password_bytes.decode('utf-8')

            # 4. AES 解密数据
            self.update_decrypt_status("步骤 4/4: AES解密文件内容...", "orange")
            encrypted_file_content_with_salt = base64.b64decode(encrypted_data_base64)
            decrypted_content = self._decrypt_data_aes(encrypted_file_content_with_salt, aes_password_b64_str)

            # 5. 写入解密后的文件
            output_file_path = input_file_path.replace(".enc", "") if input_file_path.endswith(
                ".enc") else f"{input_file_path}.dec"
            with open(output_file_path, 'wb') as f:
                f.write(decrypted_content)

            self.update_decrypt_status(f"解密成功! 已保存为 {os.path.basename(output_file_path)}", "green")
            messagebox.showinfo("成功", f"文件解密成功！\n\n已保存到:\n{output_file_path}")
            with open("log.txt", 'a', encoding='utf-8') as f:
                f.write(
                    f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DECRYPT | File: {output_file_path}\n")

        except Exception as e:
            error_msg = f"解密失败: {e}"
            self.update_decrypt_status(error_msg, "red")
            messagebox.showerror("解密错误", error_msg)
        finally:
            self.decrypt_button.config(state="normal")
            self.root.after(3000, lambda: self.update_decrypt_status("请选择加密文件和私钥", "blue"))

    def _decrypt_data_aes(self, encrypted_data_with_salt, aes_password_str):
        if not encrypted_data_with_salt.startswith(OPENSSL_SALTED_MAGIC):
            raise ValueError("加密数据缺少 'Salted__' 标识")
        salt = encrypted_data_with_salt[8:24]
        ciphertext = encrypted_data_with_salt[24:]
        kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=48, salt=salt, iterations=PBKDF2_ITERATIONS,
                         backend=default_backend())
        derived_key_iv = kdf.derive(aes_password_str.encode('utf-8'))
        cipher = Cipher(algorithms.AES(derived_key_iv[:32]), modes.CBC(derived_key_iv[32:]), backend=default_backend())
        padded_plaintext = cipher.decryptor().update(ciphertext) + cipher.decryptor().finalize()
        pad_len = padded_plaintext[-1]
        if pad_len < 1 or pad_len > 16: raise ValueError("无效的PKCS7填充长度")
        return padded_plaintext[:-pad_len]


if __name__ == "__main__":
    root = TkinterDnD.Tk()
    app = CryptoApp(root)
    root.mainloop()

