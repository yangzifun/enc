import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from cryptography.fernet import Fernet
from cryptography.fernet import InvalidToken
import os


class CryptoApp:
    def __init__(self, root):
        self.root = root
        self.root.title("文件加密工具")
        self.root.geometry("500x350")

        # 初始化加密密钥变量
        self.key = None
        self.fernet = None
        self.selected_file_path = tk.StringVar()
        self.key_status = tk.StringVar(value="状态：未加载密钥")

        # --- UI 框架 ---
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # 密钥管理部分
        key_frame = ttk.LabelFrame(main_frame, text="密钥管理")
        key_frame.pack(fill=tk.X, padx=5, pady=5)

        ttk.Button(key_frame, text="生成新密钥", command=self.generate_key).pack(side=tk.LEFT, padx=5, pady=5)
        ttk.Button(key_frame, text="加载密钥", command=self.load_key).pack(side=tk.LEFT, padx=5, pady=5)
        ttk.Label(key_frame, textvariable=self.key_status, foreground="blue").pack(side=tk.LEFT, padx=10)

        # 文件选择部分
        file_frame = ttk.LabelFrame(main_frame, text="文件操作")
        file_frame.pack(fill=tk.X, padx=5, pady=10)

        ttk.Button(file_frame, text="选择文件", command=self.select_file).pack(side=tk.LEFT, padx=5, pady=5)
        ttk.Entry(file_frame, textvariable=self.selected_file_path, state="readonly", width=50).pack(side=tk.LEFT,
                                                                                                     expand=True,
                                                                                                     fill=tk.X, padx=5)

        # 加密/解密按钮
        action_frame = ttk.Frame(main_frame)
        action_frame.pack(fill=tk.X, padx=5, pady=10)

        ttk.Button(action_frame, text="加密文件", command=self.encrypt_file).pack(fill=tk.X, pady=5)
        ttk.Button(action_frame, text="解密文件", command=self.decrypt_file).pack(fill=tk.X, pady=5)

    def generate_key(self):
        """生成一个新的密钥并保存到 key.key 文件"""
        self.key = Fernet.generate_key()
        with open("key.key", "wb") as key_file:
            key_file.write(self.key)
        self.fernet = Fernet(self.key)
        self.key_status.set("状态：已生成并加载新密钥")
        messagebox.showinfo("成功", "新的密钥已生成并保存为 'key.key'！")

    def load_key(self):
        """从文件加载密钥"""
        try:
            with open("key.key", "rb") as key_file:
                self.key = key_file.read()
            self.fernet = Fernet(self.key)
            self.key_status.set("状态：密钥已成功加载")
            messagebox.showinfo("成功", "密钥已从 'key.key' 加载。")
        except FileNotFoundError:
            messagebox.showerror("错误", "未找到 'key.key' 文件！请先生成密钥。")
            self.key_status.set("状态：加载失败，找不到密钥文件")

    def select_file(self):
        """打开文件对话框选择文件"""
        filepath = filedialog.askopenfilename()
        if filepath:
            self.selected_file_path.set(filepath)

    def process_file(self, mode):
        """统一处理加密和解密的核心逻辑"""
        if not self.fernet:
            messagebox.showwarning("警告", "请先加载或生成密钥！")
            return

        filepath = self.selected_file_path.get()
        if not filepath:
            messagebox.showwarning("警告", "请先选择一个文件！")
            return

        try:
            with open(filepath, "rb") as file:
                original_data = file.read()

            if mode == 'encrypt':
                processed_data = self.fernet.encrypt(original_data)
                output_filepath = filepath + ".enc"
                action_name = "加密"
            else:  # decrypt
                processed_data = self.fernet.decrypt(original_data)
                if filepath.endswith(".enc"):
                    output_filepath = filepath[:-4]  # 移除 .enc 后缀
                else:
                    output_filepath = filepath + ".dec"
                action_name = "解密"

            with open(output_filepath, "wb") as file:
                file.write(processed_data)

            messagebox.showinfo("成功", f"文件{action_name}成功！\n输出文件: {output_filepath}")

        except InvalidToken:
            messagebox.showerror("解密失败", "密钥不正确或文件已损坏！")
        except Exception as e:
            messagebox.showerror("发生错误", f"处理文件时发生未知错误: {e}")

    def encrypt_file(self):
        self.process_file('encrypt')

    def decrypt_file(self):
        self.process_file('decrypt')


if __name__ == "__main__":
    root = tk.Tk()
    app = CryptoApp(root)
    root.mainloop()
