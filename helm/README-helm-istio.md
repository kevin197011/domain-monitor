# Domain Monitor Helm & Istio 部署指南

这个项目包含了 Domain Monitor 应用的完整 Helm Chart 和 Istio 配置，基于原始的 `docker-compose.yml` 文件转换而来。

## 📁 目录结构

```
helm/                          # Helm Chart 目录
├── Chart.yaml                # Chart 元数据
├── values.yaml               # 默认配置值
└── templates/                # Kubernetes 模板
    ├── deployment.yaml       # 部署配置
    ├── service.yaml          # 服务配置
    ├── configmap.yaml        # 配置映射
    ├── secret.yaml           # 敏感信息
    ├── serviceaccount.yaml   # 服务账户
    ├── hpa.yaml              # 水平扩缩容
    ├── pdb.yaml              # Pod 中断预算
    ├── ingress.yaml          # Ingress 配置
    ├── gateway.yaml          # Istio Gateway
    ├── virtualservice.yaml   # Istio VirtualService
    ├── destinationrule.yaml  # Istio DestinationRule
    ├── servicemonitor.yaml   # Prometheus 监控
    └── _helpers.tpl          # 辅助模板

istio/                        # Istio 配置目录
├── peerauthentication.yaml   # mTLS 配置
├── authorizationpolicy.yaml  # 访问策略
├── telemetry.yaml           # 遥测配置
└── sidecar.yaml             # Sidecar 配置
```

## 🚀 快速开始

### 前置条件

1. **Kubernetes 集群** (v1.19+)
2. **Helm 3.0+**
3. **Istio 1.16+** (已安装和配置)
4. **Prometheus Operator** (可选，用于监控)

### 安装步骤

#### 1. 创建命名空间
```bash
kubectl create namespace domain-monitor
kubectl label namespace domain-monitor istio-injection=enabled
```

#### 2. 配置环境变量
创建 `.env` 文件或修改 `values.yaml` 中的配置：

```yaml
# values.yaml 中的关键配置
env:
  RUBY_ENV: production
  PORT: "9394"
  # 添加您的自定义环境变量

secrets:
  enabled: true
  data:
    # 添加敏感数据
    # api_key: "your-secret-api-key"
    # database_url: "your-database-connection-string"
```

#### 3. 部署应用
```bash
# 安装 Helm Chart
helm install domain-monitor ./helm \
  --namespace domain-monitor \
  --values ./helm/values.yaml

# 或者使用自定义配置
helm install domain-monitor ./helm \
  --namespace domain-monitor \
  --set image.tag=v1.0.0 \
  --set istio.virtualService.hosts[0]=your-domain.com
```

#### 4. 部署 Istio 配置
```bash
kubectl apply -f istio/ -n domain-monitor
```

## ⚙️ 配置说明

### 主要配置项

| 配置项 | 描述 | 默认值 |
|--------|------|--------|
| `replicaCount` | Pod 副本数 | `2` |
| `image.repository` | 镜像仓库 | `domain-monitor` |
| `image.tag` | 镜像标签 | `latest` |
| `service.port` | 服务端口 | `9394` |
| `istio.enabled` | 启用 Istio | `true` |
| `autoscaling.enabled` | 启用自动扩缩容 | `true` |
| `serviceMonitor.enabled` | 启用 Prometheus 监控 | `true` |

### Istio 功能特性

#### 🔒 安全性
- **mTLS**: 启用严格的双向 TLS 认证
- **访问控制**: 基于来源的授权策略
- **网络隔离**: Sidecar 配置限制出入站流量

#### 📊 可观测性
- **指标收集**: Prometheus 集成
- **访问日志**: Envoy 和 OpenTelemetry
- **分布式追踪**: Jaeger 集成

#### 🌐 流量管理
- **负载均衡**: 最少连接算法
- **熔断器**: 防止级联故障
- **重试机制**: 自动重试失败请求
- **故障注入**: 测试系统弹性

## 🔧 自定义配置

### 修改主机名
```yaml
# values.yaml
istio:
  virtualService:
    hosts:
      - your-domain.com
  gateway:
    servers:
      - hosts:
          - your-domain.com
```

### 调整资源限制
```yaml
# values.yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi
```

### 配置存储卷
```yaml
# values.yaml
persistence:
  enabled: true
  size: 10Gi
  storageClass: fast-ssd
```

## 📈 监控和可观测性

### Prometheus 监控
应用已集成 ServiceMonitor，自动暴露指标：
- HTTP 请求指标
- 应用健康状态
- 业务监控指标

### 查看监控数据
```bash
# 端口转发到 Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# 访问 Grafana 仪表板
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### Jaeger 分布式追踪
```bash
# 端口转发到 Jaeger
kubectl port-forward -n istio-system svc/jaeger 16686:16686
```

## 🚨 健康检查

应用包含以下健康检查端点：
- `/health` - 存活探针
- `/ready` - 就绪探针
- `/metrics` - Prometheus 指标

## 🔄 升级和回滚

### 升级应用
```bash
# 升级到新版本
helm upgrade domain-monitor ./helm \
  --namespace domain-monitor \
  --set image.tag=v1.1.0

# 查看升级状态
helm status domain-monitor -n domain-monitor
```

### 回滚应用
```bash
# 查看发布历史
helm history domain-monitor -n domain-monitor

# 回滚到上一个版本
helm rollback domain-monitor -n domain-monitor

# 回滚到指定版本
helm rollback domain-monitor 1 -n domain-monitor
```

## 🧪 测试验证

### 验证部署状态
```bash
# 检查 Pod 状态
kubectl get pods -n domain-monitor

# 检查服务状态
kubectl get svc -n domain-monitor

# 检查 Istio 配置
kubectl get gateway,virtualservice,destinationrule -n domain-monitor
```

### 测试应用访问
```bash
# 通过 Ingress Gateway 测试
curl -H "Host: your-domain.com" http://istio-gateway-ip/health

# 测试健康检查
kubectl exec -it deployment/domain-monitor -n domain-monitor -- curl localhost:9394/health
```

## 🔧 故障排除

### 常见问题

#### 1. Pod 启动失败
```bash
# 查看 Pod 事件
kubectl describe pod -l app.kubernetes.io/name=domain-monitor -n domain-monitor

# 查看容器日志
kubectl logs -l app.kubernetes.io/name=domain-monitor -n domain-monitor
```

#### 2. Istio 配置问题
```bash
# 检查 Istio 代理状态
istioctl proxy-status

# 分析 Envoy 配置
istioctl proxy-config cluster deployment/domain-monitor.domain-monitor
```

#### 3. 网络连接问题
```bash
# 测试服务间连通性
kubectl exec -it deployment/domain-monitor -n domain-monitor -- curl http://domain-monitor:9394/health

# 检查 Istio 网络策略
kubectl get peerauthentication,authorizationpolicy -n domain-monitor
```

## 📚 相关文档

- [Helm 官方文档](https://helm.sh/docs/)
- [Istio 官方文档](https://istio.io/latest/docs/)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Prometheus Operator](https://prometheus-operator.dev/)

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交变更
4. 推送到分支
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。