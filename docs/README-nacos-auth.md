# Domain Monitor Nacos 认证功能

## 🔐 功能概述

Domain Monitor 现在支持 Nacos 的用户名密码认证功能。这为生产环境中的配置管理提供了更高的安全性。

## ✨ 新增功能

### 1. 自动认证
- 应用启动时自动进行 Nacos 认证
- 支持访问令牌的自动管理和刷新
- 令牌过期前自动重新认证（5分钟缓冲）

### 2. 配置方式
- 通过环境变量 `NACOS_USERNAME` 和 `NACOS_PASSWORD` 配置
- 支持 Docker Compose 和 Kubernetes 部署
- 在 Kubernetes 中通过 Secret 安全管理认证信息

### 3. 智能重试
- 网络异常时自动重试认证
- 详细的认证日志记录
- 优雅的错误处理

## 🚀 快速开始

### 1. 本地开发
```bash
# 创建 .env 文件
cp env.example .env

# 编辑 .env 文件，添加认证信息
NACOS_USERNAME=your_username
NACOS_PASSWORD=your_password

# 启动应用
docker-compose up
```

### 2. Kubernetes 部署
```bash
# 使用部署脚本（推荐）
./scripts/deploy.sh \
  --domain domain-monitor.example.com \
  --nacos-user your_username \
  --nacos-pass your_password

# 或使用 Helm 直接部署
helm install domain-monitor ./helm \
  --namespace domain-monitor \
  --set secrets.data.nacos_username=$(echo -n "your_username" | base64) \
  --set secrets.data.nacos_password=$(echo -n "your_password" | base64)
```

## 📝 配置示例

### Docker Compose
```yaml
services:
  domain-monitor:
    build: .
    environment:
      - NACOS_USERNAME=nacos
      - NACOS_PASSWORD=nacos
      - NACOS_ADDR=http://nacos-server:8848
```

### Kubernetes Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nacos-auth
type: Opaque
data:
  nacos_username: bmFjb3M=  # base64: nacos
  nacos_password: bmFjb3M=  # base64: nacos
```

## 🔧 兼容性说明

- ✅ **向后兼容**：如果不配置认证信息，应用仍可正常连接到未启用认证的 Nacos 服务器
- ✅ **自动检测**：应用会自动检测是否需要认证
- ✅ **安全传输**：支持 HTTPS 连接以确保认证信息安全

## 📚 相关文档

- [完整认证配置指南](docs/nacos-auth.md)
- [Helm 部署文档](README-helm-istio.md)
- [故障排除指南](docs/nacos-auth.md#故障排除)

## 🛠️ 技术实现

### 认证流程
1. 应用启动时检查是否配置了认证信息
2. 如果配置了，向 Nacos 发送认证请求
3. 获取访问令牌并存储
4. 在后续的配置请求中自动添加认证头
5. 监控令牌过期时间，自动刷新

### 核心代码结构
```ruby
# 认证检查
def authentication_required?
  !@config.nacos_username.nil? && !@config.nacos_username.empty?
end

# 自动认证
def ensure_authentication
  if token_expired?
    authenticate
  end
end

# 请求认证头
def add_auth_header(request)
  request['Authorization'] = "Bearer #{@access_token}"
end
```

这个功能让 Domain Monitor 能够安全地集成到企业级的 Nacos 环境中。