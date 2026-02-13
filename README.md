# Local Deployment Scripts

SGLang 模型部署脚本，用于在独立服务器上运行大语言模型。

---

## 🚀 快速开始

### 1. 启动服务

```bash
# 使用 tmux
tmux new -s qwen3-coder
bash qwen3_coder_30b.sh
```

### 2. 分离会话

按 `Ctrl+B`，然后按 `D`

---

## 📋 Tmux 常用命令

```bash
# 查看所有会话
tmux ls

# 重新连接到会话
tmux attach -t qwen3-coder
# 或简写
tmux a -t qwen3-coder

# 终止会话
tmux kill-session -t qwen3-coder

# 在会话内创建新窗口
Ctrl+B, C

# 切换窗口
Ctrl+B, N  # 下一个
Ctrl+B, P  # 上一个
Ctrl+B, 0-9  # 切换到指定窗口

# 重命名会话
tmux rename-session -t qwen3-coder new-name
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

重新连接 tmux 会话即可查看日志：

```bash
tmux attach -t qwen3-coder
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

如果不需要 SSH 隧道，可以在 `service.sh` 中注释掉：

```bash
# manage_tunnel &
# TUNNEL_MGR_PID=$!
```

---

## 📁 文件结构

```
Local-Deployment-Scripts/
├── service.sh              # 核心服务管理脚本
├── qwen3_coder_30b.sh      # Qwen3-Coder 配置脚本
├── .venv/                  # Python 虚拟环境
├── logs/                   # 日志目录
└── production_scripts/     # 旧版 Slurm 脚本（参考）
```

---

## 🔄 自动重启机制

`service.sh` 内置了自动重启功能：

- ✅ SGLang 服务崩溃会自动重启（15秒后）
- ✅ SSH 隧道断开会自动重连（15秒后）
- ✅ 记录重启次数

---

## 📝 常见场景

### 场景 1：临时测试

```bash
# 前台运行，方便查看日志
bash qwen3_coder_30b.sh
# Ctrl+C 停止
```

### 场景 2：长期运行

```bash
# 使用 tmux 后台运行
tmux new -s qwen3-coder
bash qwen3_coder_30b.sh
# Ctrl+B, D 分离

# 需要查看日志时
tmux attach -t qwen3-coder
```

### 场景 3：服务器重启后恢复

```bash
# 重新连接会话（如果还在）
tmux attach -t qwen3-coder

# 如果会话已丢失，重新启动
tmux new -s qwen3-coder
bash qwen3_coder_30b.sh
```

---

## 🎯 Tmux 快速参考

| 操作 | 命令 |
|------|------|
| **创建会话** | `tmux new -s qwen3-coder` |
| **列出会话** | `tmux ls` |
| **连接会话** | `tmux a -t qwen3-coder` |
| **分离会话** | `Ctrl+B, D` |
| **终止会话** | `tmux kill-session -t qwen3-coder` |
| **新窗口** | `Ctrl+B, C` |
| **下一个窗口** | `Ctrl+B, N` |
| **上一个窗口** | `Ctrl+B, P` |

---

## 📞 需要帮助？

- 查看日志：`tmux attach -t qwen3-coder`
- 检查 GPU：`nvidia-smi`
- 测试 API：`curl http://localhost:8003/v1/models`

---

## 🔗 相关链接

- [SGLang 文档](https://github.com/sgl-project/sglang)
- [Qwen3-Coder 模型](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct)
- [Tmux 快速入门](https://github.com/tmux/tmux/wiki)
