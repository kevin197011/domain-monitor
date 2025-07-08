# Domain Monitor

一个基于Ruby的域名到期监控系统，支持WHOIS查询和Prometheus指标导出。

## 功能特性

- ✅ **域名到期监控**: 通过WHOIS查询检查域名到期时间
- ✅ **Nacos配置管理**: 支持从Nacos配置中心动态加载配置
- ✅ **Prometheus指标**: 导出标准的Prometheus监控指标
- ✅ **并发检查**: 支持多线程并发域名检查
- ✅ **健康检查**: 提供HTTP健康检查端点
- ✅ **Docker支持**: 完整的容器化部署支持

## 快速开始

### 使用Docker Compose

1. 复制环境变量文件:
```bash
cp env.example .env
```

2. 配置Nacos连接信息:
```bash
# 编辑 .env 文件，配置你的Nacos服务器信息
NACOS_ADDR=http://your-nacos-server:8848
NACOS_NAMESPACE=your-namespace
NACOS_DATA_ID=domain-monitor
NACOS_USERNAME=nacos
NACOS_PASSWORD=nacos
```

3. 启动服务:
```bash
docker-compose up -d
```

### 本地开发

1. 安装依赖:
```bash
bundle install
```

2. 设置环境变量:
```bash
export NACOS_ADDR=http://localhost:8848
export NACOS_NAMESPACE=devops
export NACOS_DATA_ID=domain-monitor
```

3. 运行程序:
```bash
bin/domain-monitor
```

## 配置说明

### Nacos配置格式

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
  metrics_port: 9394         # Prometheus指标服务端口

  # 日志设置
  log_level: debug           # 日志级别: debug, info, warn, error
```

### 环境变量

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `NACOS_ADDR` | Nacos服务器地址 | `http://192.168.1.19:8848` |
| `NACOS_NAMESPACE` | Nacos命名空间 | `devops` |
| `NACOS_DATA_ID` | 配置数据ID | `domain-monitor` |
| `NACOS_GROUP` | 配置分组 | `DEFAULT_GROUP` |
| `NACOS_USERNAME` | Nacos用户名 | `nacos` |
| `NACOS_PASSWORD` | Nacos密码 | `nacos` |

## Prometheus指标

系统导出以下Prometheus指标：

### domain_expire_days
- **类型**: Gauge
- **说明**: 域名到期剩余天数（检查失败时为-1）
- **标签**: `domain` - 域名

### domain_expired
- **类型**: Gauge
- **说明**: 域名是否过期或接近过期（1=过期/接近过期，0=正常）
- **标签**: `domain` - 域名

### domain_check_status
- **类型**: Gauge
- **说明**: 域名检查状态（1=成功，0=失败）
- **标签**: `domain` - 域名

### 指标示例

```
# TYPE domain_expire_days gauge
# HELP domain_expire_days Days until domain expiration (-1 if check failed)
domain_expire_days{domain="163.net"} 437.0
domain_expire_days{domain="google.com"} 1167.0
domain_expire_days{domain="qq.com"} -1.0
domain_expire_days{domain="baidu.com"} -1.0

# TYPE domain_expired gauge
# HELP domain_expired Whether domain is expired or close to expiry (1) or not (0)
domain_expired{domain="163.net"} 0.0
domain_expired{domain="google.com"} 0.0
domain_expired{domain="qq.com"} 0.0
domain_expired{domain="baidu.com"} 0.0

# TYPE domain_check_status gauge
# HELP domain_check_status Check status (1: success, 0: error)
domain_check_status{domain="163.net"} 1.0
domain_check_status{domain="google.com"} 1.0
domain_check_status{domain="qq.com"} 0.0
domain_check_status{domain="baidu.com"} 0.0
```

## API端点

- **健康检查**: `GET /health` - 返回 "OK"
- **指标导出**: `GET /metrics` - Prometheus格式指标

## 监控告警

可以基于以下PromQL表达式创建告警：

```promql
# 域名即将过期告警（15天内）
domain_expired == 1

# 域名检查失败告警
domain_check_status == 0

# 域名7天内过期紧急告警
domain_expire_days > 0 and domain_expire_days <= 7
```

## 开发

### 项目结构

```
lib/domain_monitor/
├── application.rb    # 主应用类
├── checker.rb        # 域名检查器
├── config.rb         # 配置管理
├── exporter.rb       # Prometheus指标导出
├── logger.rb         # 日志管理
├── nacos_client.rb   # Nacos客户端
├── whois_client.rb   # WHOIS查询客户端
└── version.rb        # 版本信息
```

### 运行测试

```bash
bundle exec rake test
```

### 构建Gem

```bash
gem build domain-monitor.gemspec
```

## 故障排除

### 常见问题

1. **WHOIS查询失败**
   - 检查网络连接
   - 某些域名可能有WHOIS防护，这是正常现象
   - 查看日志中的具体错误信息

2. **Nacos连接失败**
   - 检查Nacos服务器地址和端口
   - 验证用户名密码是否正确
   - 确认网络可达性

3. **指标不更新**
   - 检查域名检查是否正常运行
   - 查看应用日志中的错误信息

### 日志查看

```bash
# Docker环境
docker logs domain-monitor-domain-monitor-1

# 本地环境
tail -f logs/domain-monitor.log
```

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件