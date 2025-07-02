# Ruby 在线域名过期监控工具 - 开发需求文档

## 📌 项目简介

该工具旨在以 Ruby 编写一个可部署于容器中的在线域名过期监控服务，支持从 Nacos 配置中心获取监控域名列表，自动检测域名的过期状态，并以 Prometheus Exporter 格式输出检测结果。通过 gem 方式组织代码，支持命令行执行、热加载配置变更。

---

## 🧱 项目结构

```
domain-monitor/
├── bin/
│   └── domain-monitor       # 可执行文件
├── lib/
│   └── domain_monitor/
│       ├── version.rb       # 版本定义
│       ├── config.rb        # 配置读取与重载
│       ├── nacos_client.rb  # Nacos 监听客户端
│       ├── checker.rb       # 域名过期检测逻辑
│       ├── whois_client.rb  # WHOIS 查询客户端
│       └── exporter.rb      # Prometheus 格式导出
├── .env                     # 环境变量配置文件
├── Dockerfile
├── docker-compose.yml
├── domain-monitor.gemspec
└── README.md
```

---

## ✅ 功能需求

### 1. Gem 打包支持
- 使用 `domain-monitor.gemspec` 描述依赖与执行入口
- 支持通过 `gem build` / `gem install` 本地安装
- 提供 `bin/domain-monitor` 可执行入口文件

### 2. 支持 dotenv 加载本地配置
- 启动时自动加载当前目录下的 `.env` 文件
- `.env` 中包含 nacos 地址、namespace、dataId、group、检测参数等

```dotenv
NACOS_ADDR=http://localhost:8848
NACOS_NAMESPACE=dev
NACOS_GROUP=DEFAULT_GROUP
NACOS_DATA_ID=domain_list.yml
WHOIS_RETRY_TIMES=3
WHOIS_RETRY_INTERVAL=5
CHECK_INTERVAL=3600
EXPIRE_THRESHOLD_DAYS=1  # 域名过期阈值天数，小于等于此值时 domain_expired 指标为 1
```

### 3. Nacos 配置监听
- 接入 Nacos OpenAPI 实现监听配置变化
- 当目标配置（如域名列表）变更时，自动重新加载并刷新检测任务

### 4. 域名过期检测逻辑
- 通过 WHOIS 协议查询域名注册信息
- 解析域名过期时间
- 计算剩余有效天数
- 支持不同域名注册商的 WHOIS 格式解析
- 检测异常时进行重试，并记录日志
- 支持设置检测间隔时间

### 5. Prometheus Exporter 接口
- 启动 HTTP 服务（基于 Sinatra）
- 暴露 `/metrics` 接口，输出 Prometheus 指标格式

```text
# HELP domain_expire_days 域名剩余有效天数
# TYPE domain_expire_days gauge
domain_expire_days{domain="example.com"} 1

# HELP domain_expired 域名是否过期 (1: 剩余天数小于等于阈值, 0: 剩余天数大于阈值)
# TYPE domain_expired gauge
domain_expired{domain="example.com"} 1

# HELP domain_check_status 域名检查状态 (1: 正常, 0: 异常)
# TYPE domain_check_status gauge
domain_check_status{domain="example.com"} 1
```

---

## 🔄 动态配置支持

### Nacos 配置文件示例（domain_list.yml）：

```yaml
domains:
  - domain: example.com
  - domain: example.org
  - domain: example.net

global_settings:
  check_interval: 3600    # 检查间隔（秒）
  retry_times: 3         # WHOIS 查询重试次数
  retry_interval: 5      # 重试间隔（秒）
  expire_threshold: 1    # 全局过期阈值天数设置，默认为1天
```

---

## ⚙️ Docker Compose 部署支持

### compose.yml 示例：

```yaml
services:
  domain-monitor:
    build: .
    volumes:
      - ./.env:/.env
    ports:
      - "9394:9394"
    environment:
      - RUBY_ENV=production
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9394/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

---

## 🧰 技术栈

* Ruby 3.x
* Nacos OpenAPI（HTTP 协议）
* WHOIS 客户端
* Prometheus Exporter 格式
* dotenv（配置加载）
* Sinatra（Web 服务）
* Docker & Docker Compose

---

## 🚀 执行方式

```sh
# 通过 gem 安装
gem install ./domain-monitor-0.1.0.gem
domain-monitor

# 或通过 docker 启动
docker compose up --build
```

访问：[http://localhost:9394/metrics](http://localhost:9394/metrics) 查看监控数据

---

## 🗂️ 后续功能规划

* Web UI 界面展示监控结果
* 域名注册商 API 集成
* 历史数据统计和趋势分析
* 批量导入域名功能
* API 接口支持（用于第三方集成）

---

## 📄 LICENSE

MIT License
