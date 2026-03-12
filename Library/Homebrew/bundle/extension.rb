# typed: strict
# frozen_string_literal: true

require "bundle/checker/base"

module Homebrew
  module Bundle
    class Extension < Homebrew::Bundle::Checker::Base
      extend T::Helpers

      abstract!

      sig { params(subclass: T.class_of(Homebrew::Bundle::Extension)).void }
      def self.inherited(subclass)
        super
        Homebrew::Bundle.register_extension(subclass)
      end

      sig { returns(Symbol) }
      def self.type
        T.cast(const_get(:PACKAGE_TYPE), Symbol)
      end

      sig { returns(String) }
      def self.check_label
        T.cast(const_get(:PACKAGE_TYPE_NAME), String)
      end

      sig { abstract.returns(String) }
      def self.banner_name; end

      sig { abstract.returns(String) }
      def self.switch_description; end

      sig { abstract.params(name: T.untyped, options: T.untyped).returns(T.untyped) }
      def self.entry(name, options = {}); end

      sig { returns(String) }
      def self.flag
        type.to_s.tr("_", "-")
      end

      sig { returns(Symbol) }
      def self.predicate_method
        :"#{type}?"
      end

      sig { returns(T::Boolean) }
      def self.dump_supported?
        true
      end

      sig { returns(T.nilable(String)) }
      def self.dump_disable_description
        nil
      end

      sig { returns(T.nilable(T.any(Symbol, T::Array[T.untyped]))) }
      def self.dump_disable_env
        nil
      end

      sig { returns(T::Boolean) }
      def self.dump_disable_supported?
        !dump_disable_description.nil?
      end

      sig { returns(T.nilable(Symbol)) }
      def self.dump_disable_predicate_method
        return unless dump_disable_supported?

        :"no_#{type}?"
      end

      sig { returns(T.nilable(Integer)) }
      def self.check_order
        nil
      end

      sig { returns(T.nilable(Symbol)) }
      def self.check_method_name
        nil
      end

      sig { returns(T::Boolean) }
      def self.add_supported?
        true
      end

      sig { returns(T::Boolean) }
      def self.remove_supported?
        true
      end

      sig { returns(T::Boolean) }
      def self.install_supported?
        true
      end

      sig { returns(T.nilable(Symbol)) }
      def self.cleanup_method_name
        nil
      end

      sig { returns(T.nilable(String)) }
      def self.cleanup_heading
        nil
      end

      sig { returns(T::Boolean) }
      def self.cleanup_supported?
        !cleanup_heading.nil?
      end

      sig { void }
      def self.reset!; end

      sig { returns(String) }
      def self.dump
        ""
      end

      sig {
        params(
          entries:             T::Array[T.untyped],
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[T.untyped])
      }
      def self.check(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        new.find_actionable(entries, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig { params(_entries: T::Array[T.untyped]).returns(T::Array[String]) }
      def self.cleanup_items(_entries)
        []
      end

      sig { params(_items: T::Array[String]).void }
      def self.cleanup!(_items); end

      sig { params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
      def self.preinstall!(*args, **kwargs)
        raise NotImplementedError, "#{name} must implement `.preinstall!`"
      end

      sig { params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
      def self.install!(*args, **kwargs)
        raise NotImplementedError, "#{name} must implement `.install!`"
      end
    end

    class << self
      sig { params(extension: T.class_of(Extension)).void }
      def register_extension(extension)
        @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
        @extensions.reject! { |registered| registered.name == extension.name }
        @extensions << extension
      end

      sig { returns(T::Array[T.class_of(Extension)]) }
      def extensions
        @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
        @extensions
      end

      sig { params(type: T.any(Symbol, String)).returns(T.nilable(T.class_of(Extension))) }
      def extension(type)
        requested_type = type.to_sym
        extensions.find { |registered| registered.type == requested_type }
      end
    end
  end
end
