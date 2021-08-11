require 'console1984/engine'

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

module Console1984
  mattr_accessor :audit_logger

  mattr_accessor :supervisor
  mattr_accessor :protected_environments
  mattr_accessor :session_logger
  mattr_accessor :username_resolver
  mattr_reader :protected_urls, default: []
  mattr_accessor :incinerate, default: true
  mattr_accessor :incinerate_after, default: 30.days
  mattr_accessor :incineration_queue, default: "console1984_incineration"

  thread_mattr_accessor :currently_protected_urls, default: []

  class << self
    def install_support(config)
      self.protected_environments ||= config.protected_environments
      self.audit_logger = config.audit_logger || ActiveSupport::Logger.new(STDOUT)
      self.protected_urls.push(*config.protected_urls)
      self.session_logger = config.session_logger || Console1984::SessionsLogger::Database.new
      self.username_resolver = config.username_resolver || Console1984::Username::EnvResolver.new("CONSOLE_USER")

      self.supervisor = Supervisor.new
      self.protected_urls.freeze
      patch_socket_classes
    end

    def running_protected_environment?
      protected_environments.collect(&:to_sym).include?(Rails.env.to_sym)
    end

    def protecting(&block)
      protecting_connections do
        ActiveRecord::Encryption.protecting_encrypted_data(&block)
      end
    end

    private
      def patch_socket_classes
        socket_classes = [ TCPSocket, OpenSSL::SSL::SSLSocket ]
        if defined?(Redis::Connection)
          socket_classes.push(*[ Redis::Connection::TCPSocket, Redis::Connection::SSLSocket ])
        end

        socket_classes.compact.each do |socket_klass|
          socket_klass.prepend Console1984::ProtectedTcpSocket
        end
      end

      def protecting_connections
        old_currently_protected_urls = self.currently_protected_urls
        self.currently_protected_urls = protected_urls
        yield
      ensure
        self.currently_protected_urls = old_currently_protected_urls
      end
  end
end
