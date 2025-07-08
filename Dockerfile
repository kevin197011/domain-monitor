FROM ruby:3.2

# Install build dependencies
RUN apk add --no-cache build-base

# Create app directory
WORKDIR /app

# Copy gemspec and version file first
COPY Gemfile* ./
COPY domain-monitor.gemspec ./
COPY lib/domain_monitor/version.rb ./lib/domain_monitor/

# Install dependencies
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Copy the rest of the application
COPY . .

# Build and install the gem
RUN gem build domain-monitor.gemspec && \
    gem install domain-monitor-*.gem

# Make the binary executable
RUN chmod +x bin/domain-monitor

# Add lib directory to Ruby load path
ENV RUBYLIB=/app/lib

# Expose the metrics port
EXPOSE 9394

# Set the entrypoint
ENTRYPOINT ["bin/domain-monitor"]