# Nacos 认证配置指南

Domain Monitor 支持 Nacos 的用户名密码认证功能。当 Nacos 服务器启用了认证时，应用可以自动进行身份验证并获取访问令牌。

## 🔐 认证机制

应用使用以下认证流程：

1. **初始认证**：应用启动时，如果配置了用户名和密码，会自动向 Nacos 服务器进行认证
2. **令牌管理**：获取的访问令牌会被自动管理，包括过期检查和自动刷新
3. **自动重试**：如果令牌过期，应用会自动重新认证
4. **安全传输**：所有认证信息通过 HTTPS 或安全的内网传输

## ⚙️ 配置方式

### 1. 环境变量配置

在 `.env` 文件中添加 Nacos 认证信息：

```bash
# Nacos 服务器配置
NACOS_ADDR=http://nacos-server:8848
NACOS_NAMESPACE=production
NACOS_GROUP=DEFAULT_GROUP
NACOS_DATA_ID=domain_monitor.yml

# Nacos 认证信息
NACOS_USERNAME=your_username
NACOS_PASSWORD=your_password
```

### 2. Docker Compose 配置

```yaml
services:
  domain-monitor:
    build: .
    env_file:
      - .env
    environment:
      - RUBY_ENV=production
      - NACOS_USERNAME=${NACOS_USERNAME}
      - NACOS_PASSWORD=${NACOS_PASSWORD}
```

### 3. Kubernetes 配置

#### 创建 Secret
```bash
kubectl create secret generic nacos-auth \
  --from-literal=username=your_username \
  --from-literal=password=your_password \
  -n domain-monitor
```

#### 在 Helm values.yaml 中配置
```yaml
secrets:
  enabled: true
  data:
    nacos_username: "eW91cl91c2VybmFtZQ=="  # base64 encoded
    nacos_password: "eW91cl9wYXNzd29yZA=="  # base64 encoded

env:
  NACOS_ADDR: "http://nacos-server:8848"
  NACOS_NAMESPACE: "production"
  NACOS_GROUP: "DEFAULT_GROUP"
  NACOS_DATA_ID: "domain_monitor.yml"
```

## 🚀 部署示例

### 使用 Helm 部署（带认证）

```bash
# 方法 1: 通过 Helm 参数设置
helm install domain-monitor ./helm \
  --namespace domain-monitor \
  --set secrets.data.nacos_username=$(echo -n "your_username" | base64) \
  --set secrets.data.nacos_password=$(echo -n "your_password" | base64) \
  --set env.NACOS_ADDR="http://nacos-server:8848"

# 方法 2: 创建自定义 values 文件
cat > nacos-auth-values.yaml << EOF
secrets:
  enabled: true
  data:
    nacos_username: "$(echo -n 'your_username' | base64)"
    nacos_password: "$(echo -n 'your_password' | base64)"

env:
  NACOS_ADDR: "http://nacos-server:8848"
  NACOS_NAMESPACE: "production"
  NACOS_GROUP: "DEFAULT_GROUP"
  NACOS_DATA_ID: "domain_monitor.yml"
EOF

helm install domain-monitor ./helm \
  --namespace domain-monitor \
  --values nacos-auth-values.yaml
```

### 使用部署脚本

```bash
# 先设置环境变量
export NACOS_USERNAME="your_username"
export NACOS_PASSWORD="your_password"

# 使用部署脚本
./scripts/deploy.sh \
  --domain domain-monitor.example.com \
  --tag v1.0.0
```

## 🔍 认证日志

应用会记录认证相关的日志信息：

```
[INFO] Nacos - Authenticating with Nacos server
[INFO] Nacos - Successfully authenticated with Nacos
[DEBUG] Nacos - Access token expires at: 2024-01-01T15:30:00Z
[INFO] Nacos - Access token expired or expiring soon, re-authenticating
```

## 🔧 故障排除

### 常见问题

#### 1. 认证失败
```
[ERROR] Nacos - Failed to authenticate with Nacos: 401 - {"message":"username or password is wrong"}
```
**解决方案**：检查用户名和密码是否正确

#### 2. 令牌过期
```
[INFO] Nacos - Access token expired or expiring soon, re-authenticating
```
**解决方案**：这是正常行为，应用会自动重新认证

#### 3. 网络连接问题
```
[ERROR] Nacos - Authentication error: Failed to open TCP connection
```
**解决方案**：检查网络连接和 Nacos 服务器地址

### 调试技巧

1. **启用调试日志**：
   ```bash
   export LOG_LEVEL=debug
   ```

2. **检查认证状态**：
   ```bash
   kubectl logs deployment/domain-monitor -n domain-monitor | grep -i auth
   ```

3. **测试 Nacos 连接**：
   ```bash
   curl -X POST "http://nacos-server:8848/nacos/v1/auth/login" \
     -d "username=your_username&password=your_password"
   ```

## 🔒 安全最佳实践

1. **使用强密码**：确保 Nacos 用户密码足够复杂
2. **定期轮换**：定期更改认证凭据
3. **网络隔离**：确保 Nacos 服务器在安全的网络环境中
4. **加密传输**：生产环境中使用 HTTPS
5. **最小权限**：为应用创建专用的 Nacos 用户，只授予必要的权限

## 📝 认证流程详解

### 1. 初始化阶段
```ruby
# 检查是否需要认证
if authentication_required?
  authenticate
end
```

### 2. 认证过程
```ruby
# 发送认证请求
POST /nacos/v1/auth/login
Content-Type: application/x-www-form-urlencoded

username=your_username&password=your_password
```

### 3. 令牌使用
```ruby
# 在后续请求中添加认证头
Authorization: Bearer {access_token}
```

### 4. 自动刷新
```ruby
# 检查令牌是否即将过期（5分钟缓冲）
if Time.now >= (@token_expires_at - 300)
  authenticate
end
```

这样配置后，Domain Monitor 就能够安全地连接到需要认证的 Nacos 服务器了。