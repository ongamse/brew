# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class Base
        # Implement these in any subclass
        # PACKAGE_TYPE = :pkg
        # PACKAGE_TYPE_NAME = "Package"

        sig { params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[T.untyped]) }
        def exit_early_check(packages, no_upgrade:)
          work_to_be_done = packages.find do |pkg|
            !installed_and_up_to_date?(pkg, no_upgrade:)
          end

          Array(work_to_be_done)
        end

        sig { params(name: T.untyped, no_upgrade: T::Boolean).returns(String) }
        def failure_reason(name, no_upgrade:)
          reason = if no_upgrade && Bundle.upgrade_formulae.exclude?(name)
            "needs to be installed."
          else
            "needs to be installed or updated."
          end
          "#{self.class.const_get(:PACKAGE_TYPE_NAME)} #{name} #{reason}"
        end

        sig { params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[String]) }
        def full_check(packages, no_upgrade:)
          packages.reject { |pkg| installed_and_up_to_date?(pkg, no_upgrade:) }
                  .map { |pkg| failure_reason(pkg, no_upgrade:) }
        end

        sig { params(all_entries: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def checkable_entries(all_entries)
          require "bundle/skipper"
          all_entries.select { |e| e.type == self.class.const_get(:PACKAGE_TYPE) }
                     .reject { |entry| Bundle::Skipper.skip?(entry) }
        end

        sig { params(entries: T::Array[T.untyped]).returns(T.untyped) }
        def format_checkable(entries)
          checkable_entries(entries).map(&:name)
        end

        sig { params(_pkg: T.untyped, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(_pkg, no_upgrade: false)
          raise NotImplementedError
        end

        sig {
          params(
            entries:             T::Array[T.untyped],
            exit_on_first_error: T::Boolean,
            no_upgrade:          T::Boolean,
            verbose:             T::Boolean,
          ).returns(T::Array[T.untyped])
        }
        def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
          requested = format_checkable(entries)

          if exit_on_first_error
            exit_early_check(requested, no_upgrade:)
          else
            full_check(requested, no_upgrade:)
          end
        end
      end
    end
  end
end
