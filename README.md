# Domain Monitor

一个用于监控域名过期状态的Ruby应用，支持Prometheus指标输出和Nacos配置中心集成。

## 功能特性

- 🔍 **域名监控**: 定期检查域名过期状态，支持多种域名类型
- 📊 **Prometheus集成**: 输出详细的监控指标，便于接入Grafana等监控系统
- ⚙️ **Nacos配置中心**: 支持动态配置管理，实现零停机配置更新
- 🔄 **轮询配置**: 定期从Nacos拉取最新配置，支持热更新
- 🚨 **告警支持**: 支持域名即将过期和已过期的告警
- 🐳 **容器化部署**: 支持Docker和Kubernetes部署
- 🔧 **灵活配置**: 支持本地文件配置和远程配置中心

## 快速开始

### 使用Docker Compose

1. 克隆项目并配置环境变量：
```bash
git clone <repository-url>
cd domain-monitor
cp env.example .env
# 编辑 .env 文件，配置Nacos连接信息（可选）
```

2. 启动服务：
```bash
docker-compose up -d
```

3. 访问监控指标：
```bash
curl http://localhost:9394/metrics
```

### 本地运行

1. 安装依赖：
```bash
bundle install
```

2. 配置域名列表：
```bash
# 编辑 config/domains.yml 或在 Nacos 中配置
vim config/domains.yml
```

3. 启动应用：
```bash
ruby bin/domain-monitor
```

## 配置说明

### 配置方式

项目支持两种配置方式：

1. **Nacos配置中心**（推荐）: 支持动态配置更新
2. **本地文件配置**: 作为备份方案

### Nacos配置

在`.env`文件中设置Nacos连接信息：

```bash
# Nacos服务器地址
NACOS_SERVER_ADDR=http://nacos-server:8848

# Nacos认证（如果需要）
NACOS_USERNAME=your_username
NACOS_PASSWORD=your_password

# 配置标识
NACOS_DATA_ID=domain-monitor-config
NACOS_GROUP=DEFAULT_GROUP
```

在Nacos中创建配置，格式如下：

```yaml
# 域名列表
domains:
  - qq.com
  - baidu.com
  - 163.net
  - google.com

# 全局设置
settings:
  # WHOIS 查询设置
  whois_retry_times: 3        # WHOIS 查询失败重试次数
  whois_retry_interval: 5     # 重试间隔（秒）

  # 域名检查设置
  check_interval: 3600        # 域名检查间隔（秒）
  expire_threshold_days: 15    # 域名过期阈值天数
  max_concurrent_checks: 50   # 并发检查线程数

  # 监控指标设置
  metrics_port: 9394         # Prometheus 指标暴露端口
  log_level: info            # Log level (debug/info/warn/error/fatal)
  nacos_poll_interval: 60    # nacos 配置轮询检测频率（秒）
```

### 本地文件配置

如果不使用Nacos，可以直接编辑`config/domains.yml`文件，格式与Nacos配置相同。

### 配置优先级

1. **Nacos配置**（最高优先级）
2. **本地配置文件** (`config/domains.yml`)
3. **默认配置**（硬编码默认值）

## 监控指标

应用暴露以下Prometheus指标：

### 域名相关指标

- `domain_expiry_days{domain="example.com"}`: 域名距离过期的天数
- `domain_status{domain="example.com"}`: 域名检查状态 (1=成功, 0=失败)
- `domain_expired{domain="example.com"}`: 域名是否已过期 (1=已过期, 0=未过期)
- `domain_expiring_soon{domain="example.com"}`: 域名是否即将过期 (1=即将过期, 0=正常)
- `domain_last_check_timestamp{domain="example.com"}`: 最后检查时间戳

### 汇总指标

- `domain_monitor_total_domains`: 监控的域名总数
- `domain_monitor_successful_checks`: 成功检查的域名数量
- `domain_monitor_failed_checks`: 检查失败的域名数量
- `domain_monitor_expired_domains`: 已过期的域名数量
- `domain_monitor_expiring_soon_domains`: 即将过期的域名数量

### 应用信息

- `domain_monitor_info{version="x.x.x", nacos_enabled="true"}`: 应用版本和配置信息

## API端点

- `GET /metrics`: Prometheus指标
- `GET /health`: 健康检查端点
- `GET /`: 重定向到指标端点

## Kubernetes部署

项目包含完整的Helm Chart，支持一键部署到Kubernetes：

```bash
# 部署到Kubernetes
helm install domain-monitor ./helm/ \
  --set config.nacos.serverAddr=http://nacos-server:8848 \
  --set config.nacos.dataId=domain-monitor-config

# 启用Istio服务网格（可选）
helm install domain-monitor ./helm/ \
  --set istio.enabled=true \
  --set config.nacos.serverAddr=http://nacos-server:8848
```

## 配置热更新

当使用Nacos配置中心时，应用支持热更新：

1. 在Nacos控制台修改配置
2. 应用会在下一个轮询周期（默认60秒）自动检测变更
3. 配置更新后立即生效，无需重启应用
4. 所有配置变更都会记录详细日志

## 监控和告警

### Grafana仪表盘

可以使用以下PromQL查询创建监控仪表盘：

```promql
# 即将过期的域名数量
sum(domain_expiring_soon)

# 已过期的域名数量
sum(domain_expired)

# 检查失败率
sum(domain_monitor_failed_checks) / sum(domain_monitor_total_domains) * 100

# 域名过期时间分布
histogram_quantile(0.95, domain_expiry_days)
```

### 告警规则

```yaml
groups:
- name: domain-monitor
  rules:
  - alert: DomainExpired
    expr: domain_expired == 1
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "域名已过期"
      description: "域名 {{ $labels.domain }} 已经过期"

  - alert: DomainExpiringSoon
    expr: domain_expiring_soon == 1
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "域名即将过期"
      description: "域名 {{ $labels.domain }} 将在 {{ $value }} 天内过期"

  - alert: DomainCheckFailed
    expr: domain_status == 0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "域名检查失败"
      description: "域名 {{ $labels.domain }} 检查失败超过5分钟"
```

## 开发说明

### 项目结构

```
domain-monitor/
├── lib/domain_monitor/     # 核心代码
│   ├── application.rb      # 主应用程序
│   ├── config.rb          # 配置管理
│   ├── checker.rb         # 域名检查器
│   ├── exporter.rb        # Prometheus指标导出
│   ├── logger.rb          # 日志管理
│   ├── nacos_client.rb    # Nacos客户端
│   └── whois_client.rb    # WHOIS查询客户端
├── config/                 # 配置文件
├── helm/                   # Helm Chart
├── istio/                  # Istio配置
└── docs/                   # 文档
```

### 运行测试

```bash
bundle exec rspec
```

### 构建Docker镜像

```bash
docker build -t domain-monitor .
```

## 故障排除

### 常见问题

1. **Nacos连接失败**
   - 检查`NACOS_SERVER_ADDR`是否正确
   - 验证网络连通性和认证信息
   - 查看应用日志了解详细错误

2. **配置不生效**
   - 确认Nacos中的配置格式正确
   - 检查`NACOS_DATA_ID`和`NACOS_GROUP`设置
   - 等待下一个轮询周期（默认60秒）

3. **域名检查失败**
   - 检查域名格式是否正确
   - 验证WHOIS服务是否可用
   - 查看相关错误日志

### 日志查看

```bash
# Docker环境
docker logs domain-monitor

# Kubernetes环境
kubectl logs deployment/domain-monitor
```

## 贡献指南

1. Fork项目
2. 创建特性分支
3. 提交变更
4. 创建Pull Request

## 许可证

[MIT License](LICENSE)

## 更多文档

- [Nacos集成配置](docs/nacos-auth.md)
- [Helm部署指南](helm/README.md)
- [Istio服务网格配置](istio/README.md)

### 技术栈

- **Ruby**: 3.0+
- **Prometheus**: 指标收集和监控
- **Nacos**: 配置中心（可选）
- **Docker**: 容器化部署
- **Kubernetes**: 生产环境部署
- **Helm**: Kubernetes包管理
- **Istio**: 服务网格（可选）

### 架构特点

本项目严格按照 [cert-monitor](https://github.com/kevin197011/cert-monitor) 项目的架构设计：

- 🏗️ **类方法配置**: 使用类方法而不是单例模式，提高性能
- 🔄 **MD5变更检测**: 智能检测配置变更，避免不必要的更新
- 🛡️ **严格配置验证**: 完善的配置验证和错误处理
- 📊 **丰富监控指标**: 详细的Prometheus指标输出
- 🧵 **线程安全**: 多线程环境下的安全配置更新

## 部署配置

### Helm Chart 部署

项目包含完整的 Helm Chart 配置：

```bash
# 安装应用
helm install domain-monitor ./helm

# 升级应用
helm upgrade domain-monitor ./helm

# 查看状态
kubectl get pods -l app.kubernetes.io/name=domain-monitor
```

### Istio 集成

支持完整的 Istio 服务网格集成：

- 流量管理和负载均衡
- 安全策略和认证
- 监控和链路追踪
- 故障注入和恢复

详细配置请参考 `istio/` 目录。

## 监控告警

### Prometheus 指标

应用提供丰富的监控指标：

- `domain_expiry_days`: 域名过期天数
- `domain_check_errors_total`: 检查错误计数
- `domain_last_check_timestamp`: 最后检查时间
- `domain_monitor_info`: 应用信息

### Grafana 仪表板

推荐的 Grafana 查询示例：

```promql
# 即将过期的域名
domain_expiry_days < 30

# 检查失败的域名
rate(domain_check_errors_total[5m]) > 0

# 平均检查时间
avg(time() - domain_last_check_timestamp)
```

## 贡献指南

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证。详情请见 [LICENSE](LICENSE) 文件。

## 致谢

本项目架构参考了 [cert-monitor](https://github.com/kevin197011/cert-monitor) 项目的优秀设计。