# Domain Monitor

A Ruby-based domain expiration monitoring tool with Nacos integration and Prometheus metrics export.

## Features

- Monitor domain expiration dates using WHOIS protocol
- Integration with Nacos configuration center
- Prometheus metrics export
- Docker support
- Automatic configuration reload
- Retry mechanism for WHOIS queries
- Health check endpoint

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
- `NACOS_DATA_ID`: Nacos configuration ID (default: domain_list.yml)
- `WHOIS_RETRY_TIMES`: Number of retry attempts for WHOIS queries (default: 3)
- `WHOIS_RETRY_INTERVAL`: Interval between retries in seconds (default: 5)
- `CHECK_INTERVAL`: Domain check interval in seconds (default: 3600)
- `EXPIRE_THRESHOLD_DAYS`: Domain expiration threshold in days (default: 1)

## Nacos Configuration Format

```yaml
domains:
  - domain: example.com
  - domain: example.org
  - domain: example.net

global_settings:
  check_interval: 3600    # Check interval in seconds
  retry_times: 3         # WHOIS query retry times
  retry_interval: 5      # Retry interval in seconds
  expire_threshold: 1    # Expiration threshold in days
```

## Metrics

Access metrics at: http://localhost:9394/metrics

Available metrics:

- `domain_expire_days{domain="example.com"}`: Days until domain expiration
- `domain_expired{domain="example.com"}`: Whether domain is expired (1) or not (0)
- `domain_check_status{domain="example.com"}`: Check status (1: success, 0: error)

## Health Check

Access health check at: http://localhost:9394/health

## Development

1. Clone the repository
2. Install dependencies: `bundle install`
3. Run the application: `bin/domain-monitor`

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## License

MIT License