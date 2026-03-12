# typed: strict
# frozen_string_literal: true

require "bundle/extension"

module Homebrew
  module Bundle
    class Uv < Extension
      PACKAGE_TYPE = :uv
      PACKAGE_TYPE_NAME = "uv Tool"

      class << self
        sig { override.returns(String) }
        def banner_name
          "uv tools"
        end

        sig { override.returns(String) }
        def switch_description
          "`list` or `dump` uv tools."
        end

        sig { override.returns(String) }
        def dump_disable_description
          "`dump` without uv tools."
        end

        sig { override.returns(Symbol) }
        def dump_disable_env
          :bundle_dump_no_uv
        end

        sig { override.returns(Integer) }
        def check_order
          90
        end

        sig { override.returns(Symbol) }
        def check_method_name
          :uv_packages_to_install
        end

        sig { override.params(name: T.untyped, options: T.untyped).returns(T.untyped) }
        def entry(name, options = {})
          raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
          raise "options(#{options.inspect}) should be a Hash object" unless options.is_a? Hash

          unknown_options = options.keys - [:with]
          raise "unknown options(#{unknown_options.inspect}) for uv" if unknown_options.present?

          with = options[:with]
          if with && (!with.is_a?(Array) || with.any? { |requirement| !requirement.is_a?(String) })
            raise "options[:with](#{with.inspect}) should be an Array of String objects"
          end

          normalized_options = {}
          normalized_with = Array(with).map(&:strip).reject(&:empty?).uniq.sort
          normalized_options[:with] = normalized_with if normalized_with.present?

          Dsl::Entry.new(:uv, name, normalized_options)
        end

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @installed_packages = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def packages
          @packages ||= T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @packages ||= if Bundle.uv_installed?
            uv = Bundle.which_uv
            return [] if uv.nil?

            output = `#{uv} tool list --show-with --show-extras 2>/dev/null`
            parse_tool_list(output)
          else
            []
          end
        end

        sig { override.returns(String) }
        def dump
          packages.map { |package| build_entry(package) }.join("\n")
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
        def preinstall!(*args, **kwargs)
          name = args.first
          with = kwargs.fetch(:with, [])
          verbose = kwargs.fetch(:verbose, false)

          raise TypeError, "expected tool name" unless name.is_a? String
          raise TypeError, "expected with requirements" unless with.is_a? Array

          unless Bundle.uv_installed?
            puts "Installing uv. It is not currently installed." if verbose
            Bundle.brew("install", "--formula", "uv", verbose:)
            Bundle.reset!
            raise "Unable to install #{name} uv tool. uv installation failed." unless Bundle.uv_installed?
          end

          if package_installed?(name, with:)
            puts "Skipping install of #{name} uv tool. It is already installed." if verbose
            return false
          end

          true
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
        def install!(*args, **kwargs)
          name = args.first
          preinstall = kwargs.fetch(:preinstall, true)
          verbose = kwargs.fetch(:verbose, false)
          with = kwargs.fetch(:with, [])

          raise TypeError, "expected tool name" unless name.is_a? String
          raise TypeError, "expected with requirements" unless with.is_a? Array
          return true unless preinstall

          puts "Installing #{name} uv tool. It is not currently installed." if verbose

          uv = Bundle.which_uv
          return false if uv.nil?

          args = ["tool", "install", name]
          normalize_with(with).each do |requirement|
            args << "--with"
            args << requirement
          end

          success = Bundle.system(uv.to_s, *args, verbose:)
          return false unless success

          installed_packages << normalized_options(name, with:)
          true
        end

        sig { params(package: String, with: T::Array[String]).returns(T::Boolean) }
        def package_installed?(package, with: [])
          desired = normalized_options(package, with:)
          installed_packages.any? do |installed|
            installed_name = installed[:name]
            installed_with = installed[:with] || []
            installed_name == desired[:name] && installed_with == desired[:with]
          end
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def installed_packages
          @installed_packages ||= T.let(packages.dup, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
        end

        sig { params(output: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def parse_tool_list(output)
          entries = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          output.each_line do |line|
            match = line.match(/\A(\S+)\s+v\S+/)
            next unless match

            name = match[1]
            next if name.nil?

            extras_raw = line[/\[extras:\s*([^\]]+)\]/, 1]
            name = name_with_extras(name, extras_raw)
            with_raw = line[/\[with:\s*([^\]]+)\]/, 1]

            entries << {
              name: name,
              with: parse_with_requirements(with_raw),
            }
          end

          entries.sort_by { |entry| entry[:name].to_s }
        end
        private :parse_tool_list

        sig { params(name: String, extras_raw: T.nilable(String)).returns(String) }
        def name_with_extras(name, extras_raw)
          return name if extras_raw.blank?

          extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
          return name if extras.empty?

          "#{name}[#{extras.join(",")}]"
        end
        private :name_with_extras

        sig { params(with_raw: T.nilable(String)).returns(T::Array[String]) }
        def parse_with_requirements(with_raw)
          return [] if with_raw.blank?

          entries = T.let([], T::Array[String])
          with_raw.split(", ").each do |token|
            requirement = token.strip
            next if requirement.empty?

            if continuation_constraint?(requirement) && entries.any?
              last_requirement = entries.pop
              entries << "#{last_requirement}, #{normalize_constraint(requirement)}" if last_requirement
            else
              entries << requirement
            end
          end

          entries.uniq.sort
        end
        private :parse_with_requirements

        sig { params(requirement: String).returns(T::Boolean) }
        def continuation_constraint?(requirement)
          requirement.match?(/\A(?:<=|>=|!=|==|~=|<|>)\s*\S/)
        end
        private :continuation_constraint?

        sig { params(requirement: String).returns(String) }
        def normalize_constraint(requirement)
          requirement.strip.sub(/\A(<=|>=|!=|==|~=|<|>)\s+/, "\\1")
        end
        private :normalize_constraint

        sig { params(package: T::Hash[Symbol, T.untyped]).returns(String) }
        def build_entry(package)
          name = package[:name].to_s
          with = Array(package[:with])

          line = "uv #{quote(name)}"
          options = []
          if with.present?
            formatted_with = with.map { |requirement| quote(requirement) }.join(", ")
            options << "with: [#{formatted_with}]"
          end
          return line if options.empty?

          "#{line}, #{options.join(", ")}"
        end
        private :build_entry

        sig { params(value: String).returns(String) }
        def quote(value)
          value.inspect
        end
        private :quote

        sig { params(with: T::Array[String]).returns(T::Array[String]) }
        def normalize_with(with)
          with.map(&:strip).reject(&:empty?).uniq.sort
        end
        private :normalize_with

        sig { params(name: String).returns(String) }
        def normalize_name(name)
          match = name.strip.match(/\A(?<base>[^\[\]]+)(?:\[(?<extras>[^\]]+)\])?\z/)
          return name.strip unless match

          base = match[:base]
          return name.strip if base.nil?

          extras_raw = match[:extras]
          return base.strip if extras_raw.blank?

          extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
          return base.strip if extras.empty?

          "#{base.strip}[#{extras.join(",")}]"
        end
        private :normalize_name

        sig { params(name: String, with: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
        def normalized_options(name, with:)
          {
            name: normalize_name(name),
            with: normalize_with(with),
          }
        end
        private :normalized_options
      end

      sig { override.params(entries: T::Array[T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          { name: entry.name, options: entry.options || {} }
        end
      end

      sig { override.params(package: T::Hash[Symbol, T.untyped], no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        "#{self.class.check_label} #{package[:name]} needs to be installed."
      end

      sig { override.params(package: T::Hash[Symbol, T.untyped], no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        options = package[:options]
        with = if options.is_a?(Hash)
          Array(options[:with])
        else
          []
        end

        self.class.package_installed?(package[:name].to_s, with:)
      end
    end

    UvDumper = Uv
    UvInstaller = Uv

    module Checker
      UvChecker = Homebrew::Bundle::Uv
    end
  end
end
