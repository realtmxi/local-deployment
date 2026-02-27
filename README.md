# Local Deployment Scripts

SGLang 模型部署脚本，用于在独立服务器上运行大语言模型。

---

## 🚀 快速开始

### 1. 启动服务

```bash
# 推荐：systemd --user + autossh（更稳）
cp qwen3_coder_30b.service ~/.config/systemd/user/
cp qwen3_coder_30b_tunnel.service ~/.config/systemd/user/
chmod +x qwen3_coder_30b_tunnel.sh

systemctl --user daemon-reload
systemctl --user enable --now qwen3_coder_30b.service qwen3_coder_30b_tunnel.service
```

### 2. 检查状态

```bash
systemctl --user status qwen3_coder_30b.service
systemctl --user status qwen3_coder_30b_tunnel.service
```

---

## 📋 systemd 常用命令

```bash
# 查看服务状态
systemctl --user status qwen3_coder_30b.service
systemctl --user status qwen3_coder_30b_tunnel.service

# 启动服务
systemctl --user start qwen3_coder_30b.service qwen3_coder_30b_tunnel.service

# 停止服务
systemctl --user stop qwen3_coder_30b.service qwen3_coder_30b_tunnel.service

# 重启服务
systemctl --user restart qwen3_coder_30b.service qwen3_coder_30b_tunnel.service

# 查看日志
journalctl --user -u qwen3_coder_30b.service -f
journalctl --user -u qwen3_coder_30b_tunnel.service -f

# 检查是否开机自启
systemctl --user is-enabled qwen3_coder_30b.service
systemctl --user is-enabled qwen3_coder_30b_tunnel.service
```

---

## 🔍 监控和测试

### 查看 GPU 使用情况

```bash
watch -n 1 nvidia-smi
```

### 测试 API

```bash
# 查看可用模型
curl http://localhost:8003/v1/models

# Chat API 测试
curl http://localhost:8003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "你好，请介绍一下你自己"}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }'

# 代码生成测试
curl http://localhost:8003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "用 Python 写一个快速排序"}
    ],
    "max_tokens": 512
  }'
```

### 查看服务日志

使用 systemd 日志：

```bash
journalctl --user -u qwen3_coder_30b.service -f
journalctl --user -u qwen3_coder_30b_tunnel.service -f
```

---

## ⚙️ 配置说明

### 当前配置

- **模型**: Qwen3-Coder-30B-A3B-Instruct
- **端口**: 8003
- **GPU**: 单卡（GPU 0）
- **上下文长度**: 32K tokens
- **显存使用**: 90%

### 修改配置

编辑 `qwen3_coder_30b.sh`:

```bash
MODEL_PATH="/home/murphy/models/Qwen3-Coder-30B-A3B-Instruct"
PORT=8003
TP_SIZE=1  # 张量并行大小（1=单卡，2=双卡）
REMOTE_SSH_URL="murphy@freeinference.org"
```

### 使用双卡

```bash
# 在 qwen3_coder_30b.sh 中修改
TP_SIZE=2
export CUDA_VISIBLE_DEVICES=0,1
```

---

## 🛠️ 故障排查

### 服务无法启动

1. **检查 GPU**
   ```bash
   nvidia-smi
   ```

2. **检查端口占用**
   ```bash
   lsof -i :8003
   ```

3. **检查模型文件**
   ```bash
   ls -lh ~/models/Qwen3-Coder-30B-A3B-Instruct/*.safetensors | wc -l
   # 应该显示 16
   ```

### 显存不足

编辑 `service.sh`，降低显存使用：

```bash
--mem-fraction-static 0.80  # 从 0.90 降到 0.80
--context-length 16384      # 从 32768 降到 16384
```

### SSH 隧道连接失败

测试 SSH 连接：

```bash
ssh murphy@freeinference.org "echo OK"
```

重启隧道服务（推荐）：

```bash
systemctl --user restart qwen3_coder_30b_tunnel.service
systemctl --user status qwen3_coder_30b_tunnel.service
```

手动验证远端映射：

```bash
ssh murphy@freeinference.org "curl -s -o /dev/null -w 'http_code=%{http_code} exit=%{exitcode}\n' http://localhost:8003/v1/models"
```

---

## 📁 文件结构

```
Local-Deployment-Scripts/
├── service.sh              # 核心服务管理脚本
├── qwen3_coder_30b.sh      # Qwen3-Coder 配置脚本
├── qwen3_coder_30b.service # Qwen systemd 用户服务
├── qwen3_coder_30b_tunnel.sh      # autossh 反向隧道脚本
├── qwen3_coder_30b_tunnel.service # 隧道 systemd 用户服务
├── .venv/                  # Python 虚拟环境
├── logs/                   # 日志目录
└── production_scripts/     # 旧版 Slurm 脚本（参考）
```

---

## 🔄 自动重启机制

`qwen3_coder_30b.service` + `qwen3_coder_30b_tunnel.service` 提供自动恢复：

- ✅ SGLang 进程崩溃自动重启
- ✅ SSH 反向隧道断开自动重连（autossh + systemd）
- ✅ 机器重启后自动恢复（配合 `systemctl --user enable` + linger）

---

## 📝 常见场景

### 场景 1：临时测试

```bash
# 前台直接运行（绕过 systemd，仅用于临时 debug）
bash qwen3_coder_30b.sh
# Ctrl+C 停止
```

### 场景 2：长期运行

```bash
# systemd 后台运行（推荐）
systemctl --user enable --now qwen3_coder_30b.service qwen3_coder_30b_tunnel.service

# 需要查看日志时
journalctl --user -u qwen3_coder_30b.service -f
```

### 场景 3：服务器重启后恢复

```bash
# 检查用户服务是否自启
systemctl --user status qwen3_coder_30b.service
systemctl --user status qwen3_coder_30b_tunnel.service

# 如未启用，开启开机自启
systemctl --user enable qwen3_coder_30b.service qwen3_coder_30b_tunnel.service
loginctl enable-linger "$USER"
```

---

## 🎯 systemd 快速参考

| 操作 | 命令 |
|------|------|
| **启动服务** | `systemctl --user start qwen3_coder_30b.service qwen3_coder_30b_tunnel.service` |
| **停止服务** | `systemctl --user stop qwen3_coder_30b.service qwen3_coder_30b_tunnel.service` |
| **重启服务** | `systemctl --user restart qwen3_coder_30b.service qwen3_coder_30b_tunnel.service` |
| **查看状态** | `systemctl --user status qwen3_coder_30b.service` |
| **查看日志** | `journalctl --user -u qwen3_coder_30b.service -f` |
| **启用自启** | `systemctl --user enable qwen3_coder_30b.service qwen3_coder_30b_tunnel.service` |
| **检查自启** | `systemctl --user is-enabled qwen3_coder_30b.service` |

---

## 📞 需要帮助？

- 查看模型日志：`journalctl --user -u qwen3_coder_30b.service -f`
- 查看隧道日志：`journalctl --user -u qwen3_coder_30b_tunnel.service -f`
- 检查 GPU：`nvidia-smi`
- 测试 API：`curl http://localhost:8003/v1/models`

---

## 🔗 相关链接

- [SGLang 文档](https://github.com/sgl-project/sglang)
- [Qwen3-Coder 模型](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct)
