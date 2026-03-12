# typed: strict
# frozen_string_literal: true

require "bundle/extension"

module Homebrew
  module Bundle
    class Go < Extension
      PACKAGE_TYPE = :go
      PACKAGE_TYPE_NAME = "Go Package"

      class << self
        sig { override.returns(String) }
        def banner_name
          "Go packages"
        end

        sig { override.returns(String) }
        def switch_description
          "`list` or `dump` Go packages."
        end

        sig { override.returns(String) }
        def dump_disable_description
          "`dump` without Go packages."
        end

        sig { override.returns(Symbol) }
        def dump_disable_env
          :bundle_dump_no_go
        end

        sig { override.returns(Integer) }
        def check_order
          70
        end

        sig { override.returns(Symbol) }
        def check_method_name
          :go_packages_to_install
        end

        sig { override.params(name: T.untyped, options: T.untyped).returns(T.untyped) }
        def entry(name, options = {})
          raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
          raise "options(#{options.inspect}) should be a Hash object" unless options.is_a? Hash
          raise "unknown options(#{options.keys.inspect}) for go" if options.present?

          Dsl::Entry.new(:go, name)
        end

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { returns(T::Array[String]) }
        def packages
          @packages ||= T.let(nil, T.nilable(T::Array[String]))
          @packages ||= if Bundle.go_installed?
            go = Bundle.which_go
            return [] if go.nil?

            ENV["GOBIN"] = ENV.fetch("HOMEBREW_GOBIN", nil)
            ENV["GOPATH"] = ENV.fetch("HOMEBREW_GOPATH", nil)
            gobin = `#{go} env GOBIN`.chomp
            gopath = `#{go} env GOPATH`.chomp
            bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin

            return [] unless File.directory?(bin_dir)

            binaries = Dir.glob("#{bin_dir}/*").select do |file|
              File.executable?(file) && !File.directory?(file) && !File.symlink?(file)
            end

            binaries.filter_map do |binary|
              output = `#{go} version -m "#{binary}" 2>/dev/null`
              next if output.empty?

              lines = output.split("\n")
              path_line = lines.find { |line| line.strip.start_with?("path\t") }
              next unless path_line

              # Parse the output to find the path line
              # Format: "\tpath\tgithub.com/user/repo"
              parts = path_line.split("\t")
              # Extract the package path (second field after splitting by tab)
              # The line format is: "\tpath\tgithub.com/user/repo"
              path = parts[2]&.strip

              # `command-line-arguments` is a dummy package name for binaries built
              # from a list of source files instead of a specific package name.
              # https://github.com/golang/go/issues/36043
              next if path == "command-line-arguments"

              path
            end.compact.uniq
          else
            []
          end
        end

        sig { override.returns(String) }
        def dump
          packages.map { |name| "go \"#{name}\"" }.join("\n")
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
        def preinstall!(*args, **kwargs)
          name = args.first
          verbose = kwargs.fetch(:verbose, false)

          raise TypeError, "expected package name" unless name.is_a? String

          unless Bundle.go_installed?
            puts "Installing go. It is not currently installed." if verbose
            Bundle.brew("install", "--formula", "go", verbose:)
            raise "Unable to install #{name} package. Go installation failed." unless Bundle.go_installed?
          end

          if package_installed?(name)
            puts "Skipping install of #{name} Go package. It is already installed." if verbose
            return false
          end

          true
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
        def install!(*args, **kwargs)
          name = args.first
          preinstall = kwargs.fetch(:preinstall, true)
          verbose = kwargs.fetch(:verbose, false)

          raise TypeError, "expected package name" unless name.is_a? String
          return true unless preinstall

          puts "Installing #{name} Go package. It is not currently installed." if verbose

          go = Bundle.which_go
          return false if go.nil?
          return false unless Bundle.system(go.to_s, "install", "#{name}@latest", verbose:)

          installed_packages << name
          true
        end

        sig { params(package: String).returns(T::Boolean) }
        def package_installed?(package)
          installed_packages.include? package
        end

        sig { returns(T::Array[String]) }
        def installed_packages
          @installed_packages ||= T.let(packages.dup, T.nilable(T::Array[String]))
        end
      end

      sig { override.params(package: String, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        "#{self.class.check_label} #{package} needs to be installed."
      end

      sig { override.params(package: String, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        self.class.package_installed?(package)
      end
    end

    GoDumper = Go
    GoInstaller = Go

    module Checker
      GoChecker = Homebrew::Bundle::Go
    end
  end
end
