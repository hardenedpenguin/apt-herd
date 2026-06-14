#!/usr/bin/env ruby
# apt-herd - Herd apt maintenance across Debian systems on VPN or local LAN via SSH
# Usage: ./apt-herd.rb [options] [host1 host2 ...]
# Requires: sudo gem3.3 install net-ssh ed25519 bcrypt_pbkdf (or: sudo bundle3.3 install --gemfile=Gemfile.apt-herd)

gemfile = File.expand_path('Gemfile.apt-herd', __dir__)
if File.exist?(gemfile)
  ENV['BUNDLE_GEMFILE'] ||= gemfile
  begin
    require 'bundler/setup'
  rescue LoadError, Bundler::GemNotFound
    # Fall back to system gems (e.g. sudo gem3.3 install)
  end
end

require 'net/ssh'
require 'optparse'
require 'yaml'
require 'pathname'
require 'etc'

CONFIG_PATH = Pathname(__dir__) + 'apt-herd.yaml'
DEFAULT_SSH_CONFIG = File.expand_path('~/.ssh/config')

def parse_ssh_config(path = DEFAULT_SSH_CONFIG)
  path = File.expand_path(path)
  return { hosts: [], host_opts: {} } unless File.readable?(path)

  hosts = []
  host_opts = {}
  current_names = nil
  current_opts = nil

  File.readlines(path).each do |line|
    # Strip but keep track of continuation (leading space = same block)
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?('#')

    if stripped.match?(/^\s*Host\s+/i)
      # Save previous block
      if current_names && current_names.any?
        current_names.each { |n| host_opts[n] = current_opts.dup }
        hosts.concat(current_names)
      end
      names = stripped.sub(/\A\s*Host\s+/i, '').split(/\s+/)
      current_names = names.reject { |n| n == '*' || n.include?('*') || n.include?('?') }
      current_opts = { host_name: nil, user: nil, port: nil, keys: [] }
      next
    end

    next unless current_opts
    key, val = stripped.split(/\s+/, 2)
    next unless val
    key = key.to_s.downcase
    case key
    when 'hostname'
      current_opts[:host_name] = val.strip
    when 'user'
      current_opts[:user] = val.strip
    when 'port'
      current_opts[:port] = val.to_i
    when 'identityfile'
      current_opts[:keys] << File.expand_path(val.strip.gsub(/\A["']|["']\z/, ''))
    end
  end

  if current_names && current_names.any?
    current_names.each { |n| host_opts[n] = current_opts.dup }
    hosts.concat(current_names)
  end

  { hosts: hosts.uniq, host_opts: host_opts }
rescue StandardError => e
  warn "Could not read SSH config #{path}: #{e.message}"
  { hosts: [], host_opts: {} }
end

def load_config(path = CONFIG_PATH)
  path = Pathname(path).expand_path
  return {} unless path.exist?
  YAML.load_file(path) || {}
rescue Psych::SyntaxError => e
  warn "Config parse error: #{e.message}"
  {}
end

def hosts_from_config(config)
  list = config['hosts'] || []
  list = [list] unless list.is_a?(Array)
  list.map { |h| h.is_a?(Hash) ? h['host'] || h[:host] : h.to_s }.compact
end

def ssh_options_from_config(config)
  opts = config['ssh'] || {}
  {
    user: opts['user'] || opts[:user] || ENV['USER'],
    port: (opts['port'] || opts[:port] || 22).to_i,
    keys: Array(opts['keys'] || opts[:keys]).compact,
    timeout: (opts['timeout'] || 10).to_i,
    auth_methods: %w[publickey keyboard-interactive password]
  }
end

def run_remote(host, ssh_opts, dry_run: false, host_ssh_config: nil, verbose: false)
  quiet = verbose ? '' : ' -qq'
  dfe = 'sudo DEBIAN_FRONTEND=noninteractive'
  cmd = [
    "sudo apt update#{quiet}",
    "#{dfe} apt full-upgrade -y#{quiet}",
    "#{dfe} apt autoremove --purge -y#{quiet}",
    'sudo apt clean'
  ].join(' && ')
  target = (host_ssh_config && host_ssh_config[:host_name]) ? host_ssh_config[:host_name] : host
  # For hosts from SSH config: use that block's User or current user only (never YAML/CLI user)
  user = if host_ssh_config
           host_ssh_config[:user] || ENV['USER']
         else
           ssh_opts[:user] || ENV['USER']
         end
  # Cron often leaves USER unset; Net::SSH deprecates nil user
  user = Etc.getpwuid(Process.uid).name if user.nil? || user.to_s.strip.empty?
  opts = ssh_opts.dup
  opts[:user] = user
  if host_ssh_config
    opts[:port] = host_ssh_config[:port] if host_ssh_config[:port]
    # Use only this host's keys from SSH config (or none → Net::SSH uses default agent/keys)
    opts[:keys] = host_ssh_config[:keys].any? ? host_ssh_config[:keys] : nil
    opts.delete(:keys) if opts[:keys].nil? || opts[:keys].empty?
  end

  if dry_run
    puts "[#{host}] (dry-run) #{user}@#{target} - would run: #{cmd}"
    return { host: host, ok: true, out: '', err: '' }
  end

  out, err = '', ''
  exit_status = nil
  Net::SSH.start(target, user, opts) do |ssh|
    status = {}
    ssh.exec!(cmd, status: status) do |_ch, stream, data|
      (stream == :stderr ? err : out) << data
    end
    exit_status = status[:exit_code]
  end
  ok = exit_status == 0
  { host: host, ok: ok, out: out, err: err }
rescue Net::SSH::AuthenticationFailed => e
  { host: host, ok: false, out: '', err: "SSH auth failed: #{e.message}" }
rescue Net::SSH::ConnectionTimeout, Errno::ETIMEDOUT => e
  { host: host, ok: false, out: '', err: "Connection timeout: #{e.message}" }
rescue StandardError => e
  { host: host, ok: false, out: '', err: e.message }
end

def main
  use_ssh_config_cli = false
  options = {
    user: nil,
    port: 22,
    keys: [],
    timeout: 10,
    dry_run: false,
    verbose: false,
    config_path: nil,
    use_ssh_config: nil
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($0)} [options] [host1 host2 ...]"
    opts.on('-u', '--user USER', 'SSH user') { |u| options[:user] = u }
    opts.on('-p', '--port PORT', Integer, 'SSH port') { |p| options[:port] = p }
    opts.on('-k', '--key KEY', 'SSH key path (can repeat)') { |k| options[:keys] << k }
    opts.on('-t', '--timeout SEC', Integer, 'SSH timeout') { |t| options[:timeout] = t }
    opts.on('-n', '--dry-run', 'Only print what would be run') { options[:dry_run] = true }
    opts.on('-v', '--verbose', 'Show command output') { options[:verbose] = true }
    opts.on('-c', '--config PATH', 'Config file path') { |c| options[:config_path] = c }
    opts.on('--ssh-config', 'Use hosts from ~/.ssh/config') { use_ssh_config_cli = true }
    opts.on('-h', '--help', 'Show this help') { puts opts; exit }
  end.parse!

  config_file = options[:config_path] || CONFIG_PATH.to_s
  config = load_config(config_file)
  default_opts = ssh_options_from_config(config)
  config_hosts = hosts_from_config(config)

  options[:use_ssh_config] = true if use_ssh_config_cli
  options[:use_ssh_config] = config['use_ssh_config'] if options[:use_ssh_config].nil?
  options[:user] ||= default_opts[:user]
  options[:port] ||= default_opts[:port]
  options[:keys] = default_opts[:keys] if default_opts[:keys].any? && options[:keys].empty?
  options[:timeout] ||= default_opts[:timeout]

  ssh_config_path = (config['ssh_config_path'] || config[:ssh_config_path] || DEFAULT_SSH_CONFIG).to_s
  ssh_config_path = File.expand_path(ssh_config_path)

  ssh_config_host_opts = {}
  hosts = ARGV.dup
  if hosts.empty?
    hosts = config_hosts if config_hosts.any?
    if options[:use_ssh_config]
      parsed = parse_ssh_config(ssh_config_path)
      ssh_config_host_opts = parsed[:host_opts]
      ssh_hosts = parsed[:hosts]
      hosts = hosts.any? ? (hosts + ssh_hosts).uniq : ssh_hosts
    end
  end

  if hosts.empty?
    warn "No hosts given. Use -h for help, pass hostnames, set 'hosts' in #{config_file}, or use --ssh-config / use_ssh_config: true"
    exit 1
  end

  default_user = options[:user] || ENV['USER']
  ssh_opts = {
    user: default_user,
    port: options[:port],
    keys: options[:keys].any? ? options[:keys] : nil,
    timeout: options[:timeout],
    auth_methods: %w[publickey keyboard-interactive password]
  }
  ssh_opts.delete(:keys) if ssh_opts[:keys].nil? || ssh_opts[:keys].empty?

  results = []
  hosts.each do |host|
    host = host.strip
    print "Updating #{host}..." unless options[:dry_run]
    host_opts = ssh_config_host_opts[host]
    r = run_remote(host, ssh_opts, dry_run: options[:dry_run], host_ssh_config: host_opts, verbose: options[:verbose])
    results << r
    if options[:dry_run]
      # already printed
    else
      puts r[:ok] ? ' OK' : ' FAILED'
      if options[:verbose]
        puts r[:out] if r[:out].to_s != ''
        warn r[:err] if r[:err].to_s != ''
      end
    end
  end

  failed = results.reject { |r| r[:ok] }
  if failed.any?
    warn "\nFailed: #{failed.map { |r| r[:host] }.join(', ')}"
    failed.each { |r| warn "  #{r[:host]}: #{r[:err]}" }
    exit 1
  end
end

main if __FILE__ == $0
