# frozen_string_literal: true

require 'time'

task default: %w[push]

task :install do
  system 'gem uninstall domain-monitor -aIx'
  system 'gem build domain-monitor.gemspec'
  system 'gem install domain-monitor-0.1.0.gem'
end

task :push do
  system 'rubocop -A'
  system 'git add .'
  system "git commit -m 'Update #{Time.now}.'"
  system 'git pull'
  system 'git push origin main'
end

task :docker do
  system 'export COMPOSE_BAKE=true'
  system 'docker compose up --build -d'
  system 'docker compose logs -f'
end
