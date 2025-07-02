FROM ruby:3.2-alpine

# Install build dependencies
RUN apk add --no-cache build-base

# Create app directory
WORKDIR /app

# Copy gemspec and Gemfile
COPY domain-monitor.gemspec ./
COPY lib/domain_monitor/version.rb ./lib/domain_monitor/

# Install dependencies
RUN bundle install

# Copy the rest of the application
COPY . .

# Make the binary executable
RUN chmod +x bin/domain-monitor

# Expose the metrics port
EXPOSE 9394

# Set the entrypoint
ENTRYPOINT ["bin/domain-monitor"]