# Domain Monitor

A Ruby-based domain expiration monitoring tool with Nacos integration and Prometheus metrics export.

## Features

- Monitor domain expiration dates using WHOIS protocol
- Integration with Nacos configuration center
- Prometheus metrics export
- Docker support
- Automatic configuration reload (30s polling interval)
- Retry mechanism for WHOIS queries
- Multi-threaded domain checking
- Health check endpoint
- Intelligent encoding detection for WHOIS responses
- Comprehensive logging

## Requirements

- Ruby >= 3.0.0
- Docker (optional)

## Installation

### Using Gem

```bash
# Build the gem
gem build domain-monitor.gemspec

# Install the gem
gem install domain-monitor-0.1.0.gem
```

### Using Docker

```bash
# Build and run with Docker Compose
docker compose up --build
```

## Configuration

Create a `.env` file based on `.env.template`:

```bash
cp .env.template .env
```

Available environment variables:

- `NACOS_ADDR`: Nacos server address (default: http://localhost:8848)
- `NACOS_NAMESPACE`: Nacos namespace (default: dev)
- `NACOS_GROUP`: Nacos configuration group (default: DEFAULT_GROUP)
- `NACOS_DATA_ID`: Nacos configuration ID (default: domain_monitor.yml)
- `WHOIS_RETRY_TIMES`: Number of retry attempts for WHOIS queries (default: 3)
- `WHOIS_RETRY_INTERVAL`: Interval between retries in seconds (default: 5)
- `CHECK_INTERVAL`: Domain check interval in seconds (default: 3600)
- `EXPIRE_THRESHOLD_DAYS`: Domain expiration threshold in days (default: 1)
- `DOMAIN_CHECK_THREADS`: Number of threads for parallel domain checking (default: 50)
- `METRICS_PORT`: Port for metrics and health check endpoints (default: 9394)

## Nacos Configuration Format

```yaml
# Domain List
domains:
  - qq.com
  - baidu.com
  - 163.net
  - google.com

# Global Settings
settings:
  # WHOIS Query Settings
  whois_retry_times: 3        # Number of retry attempts for WHOIS queries
  whois_retry_interval: 5     # Retry interval in seconds

  # Domain Check Settings
  check_interval: 3600        # Domain check interval in seconds
  expire_threshold_days: 1    # Domain expiration threshold in days
  check_threads: 50          # Number of concurrent check threads

  # Metrics Settings
  metrics_port: 9394         # Prometheus metrics export port
```

## Metrics

Access metrics at: http://localhost:9394/metrics

Available metrics:

- `domain_expire_days{domain="example.com"}`: Days until domain expiration (-1 if check failed)
- `domain_expired{domain="example.com"}`: Whether domain is expired or close to expiry (1) or not (0)
- `domain_check_status{domain="example.com"}`: Check status (1: success, 0: error)

## Health Check

Access health check at: http://localhost:9394/health

Response format:
```json
{"status":"up"}
```

## Error Handling

The tool includes comprehensive error handling:

- WHOIS query timeouts (15 seconds per attempt)
- Automatic retries for failed queries
- Intelligent encoding detection for WHOIS responses
- Multiple date format parsing attempts
- Thread pool management
- Graceful shutdown handling

## Development

1. Clone the repository
2. Install dependencies: `bundle install`
3. Run the application: `bin/domain-monitor`

### Dependencies

Runtime dependencies:
- activesupport (~> 7.1)
- concurrent-ruby (~> 1.2)
- dotenv (~> 2.8)
- prometheus-client (~> 4.1)
- rack (~> 2.2)
- sinatra (~> 3.1)
- webrick (~> 1.8)
- whois (~> 5.1)

Development dependencies:
- bundler (~> 2.0)
- rake (~> 13.0)
- rspec (~> 3.0)
- rubocop (~> 1.57)

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## License

MIT License