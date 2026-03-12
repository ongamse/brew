# typed: true
# frozen_string_literal: true

require "bundle/checker/base"
require "bundle/extensions"

module Homebrew
  module Bundle
    module Checker
      CheckResult = Struct.new :work_to_be_done, :errors
      CheckStep = T.type_alias { T.any(Symbol, T.class_of(Homebrew::Bundle::Extension)) }

      CORE_CHECKS = T.let([
        [10, :taps_to_tap],
        [20, :casks_to_install],
        [30, :extensions_to_install],
        [40, :apps_to_install],
        [50, :formulae_to_install],
        [60, :formulae_to_start],
        [80, :cargo_packages_to_install],
        [100, :flatpaks_to_install],
      ].freeze, T::Array[[Integer, Symbol]])

      def self.check(global: false, file: nil, exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brewfile"
        @dsl ||= Brewfile.read(global:, file:)

        errors = []
        enumerator = exit_on_first_error ? :find : :map

        work_to_be_done = check_steps.public_send(enumerator) do |check_step|
          check_errors = run_check_step(check_step, exit_on_first_error:, no_upgrade:, verbose:)
          any_errors = check_errors.any?
          errors.concat(check_errors) if any_errors
          any_errors
        end

        work_to_be_done = Array(work_to_be_done).flatten.any?

        CheckResult.new work_to_be_done, errors
      end

      def self.casks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/cask_checker"
        Homebrew::Bundle::Checker::CaskChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.formulae_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brew_checker"
        Homebrew::Bundle::Checker::BrewChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.taps_to_tap(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/tap_checker"
        Homebrew::Bundle::Checker::TapChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.apps_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/mac_app_store_checker"
        Homebrew::Bundle::Checker::MacAppStoreChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.extensions_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/vscode_extension_checker"
        Homebrew::Bundle::Checker::VscodeExtensionChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.formulae_to_start(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brew_service_checker"
        Homebrew::Bundle::Checker::BrewServiceChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.go_packages_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        Homebrew::Bundle::Go.check(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.cargo_packages_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/cargo_checker"
        Homebrew::Bundle::Checker::CargoChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.flatpaks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/flatpak_checker"
        Homebrew::Bundle::Checker::FlatpakChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.uv_packages_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        Homebrew::Bundle::Uv.check(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.reset!
        require "bundle/cask_dumper"
        require "bundle/formula_dumper"
        require "bundle/mac_app_store_dumper"
        require "bundle/tap_dumper"
        require "bundle/brew_services"

        @dsl = nil
        Homebrew::Bundle::CaskDumper.reset!
        Homebrew::Bundle::FormulaDumper.reset!
        Homebrew::Bundle::MacAppStoreDumper.reset!
        Homebrew::Bundle::TapDumper.reset!
        Homebrew::Bundle::BrewServices.reset!
        Homebrew::Bundle.extensions.each(&:reset!)
      end

      sig { returns(T::Array[CheckStep]) }
      def self.check_steps
        extension_checks = T.let([], T::Array[[Integer, CheckStep]])

        Homebrew::Bundle.extensions.each do |extension|
          check_order = extension.check_order
          next if check_order.nil?

          extension_checks << [check_order, extension.check_method_name || extension]
        end

        (CORE_CHECKS + extension_checks).sort_by { |check_order, _| check_order }.map(&:last)
      end

      sig {
        params(
          check_step:          CheckStep,
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[T.untyped])
      }
      def self.run_check_step(check_step, exit_on_first_error:, no_upgrade:, verbose:)
        if check_step.is_a?(Symbol)
          public_send(check_step, exit_on_first_error:, no_upgrade:, verbose:)
        else
          check_step.check(
            @dsl.entries,
            exit_on_first_error:, no_upgrade:, verbose:,
          )
        end
      end
    end
  end
end
