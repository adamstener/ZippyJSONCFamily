module Fastlane
  module Actions
    require 'fastlane_core/ui/ui'
    require 'fastlane/actions/xcodebuild'
    require 'fastlane/actions/zip'
    require 'fileutils'

    class SmartCreateXcframeworkAction < Action
      # Runs the smart_create_xcframework action
      def self.run(params)
        frameworks_symbols = {}
        xcframework_name = (params[:name] || params[:scheme]).delete_suffix('.xcframework')

        Dir.mktmpdir do |tmp|
          sdks(params[:platforms]).each do |sdk|
            xcarchive_path = "#{tmp}/#{sdk}/#{xcframework_name}.xcarchive"

            FastlaneCore::UI.important("▸ Archiving #{scheme(params[:scheme], sdk)} for #{sdk}")

            XcarchiveAction.run(
              archive_path: xcarchive_path,
              clean: true,
              configuration: params[:configuration],
              destination: platform_destination(sdk),
              project: params[:project],
              scheme: scheme(params[:scheme], sdk),
              workspace: params[:workspace],
              xcargs: xcode_arguments(params)
            )

            set_version_and_build_number(xcarchive_path, params[:version], params[:build_number])

            frameworks_symbols[sdk] = frameworks_symbols(xcarchive_path, xcframework_name, params[:name])
          end

          Dir.chdir(tmp) do
            FastlaneCore::UI.important("▸ Creating #{xcframework_name}.xcframework")

            if params[:enable_library_evolution]
              create_xcframework(frameworks_symbols, xcframework_name)
            else
              generate_xcframework(frameworks_symbols, xcframework_name)
              generate_xcframework_info_plist(frameworks_symbols, xcframework_name)
            end

            FastlaneCore::UI.important("▸ Zipping #{xcframework_name}.xcframework")

            ZipAction.run(
              path: "#{xcframework_name}.xcframework",
              output_path: params[:zip_destination],
              verbose: false,
              symlinks: true
            )
          end
        end
      end

      # Creates an XCFramework from the supplied frameworks and debug symbols
      def self.create_xcframework(frameworks_symbols, xcframework)
        FastlaneCore::UI.message "▸ Creating #{xcframework}.xcframework via xcodebuild -create-xcframework"

        create_xcframework = ['xcodebuild -create-xcframework'].tap do |args|
          frameworks_symbols.each do |_sdk, details|
            args << "-framework #{details[:framework]}"
            args << "-debug-symbols #{details[:dsym]}" unless details[:dsym].nil?
            details[:bc_symbol_maps].each do |path|
              args << "-debug-symbols #{path}"
            end
          end
          args << '-allow-internal-distribution'
          args << "-output #{xcframework}.xcframework"
        end.join(" \\\n  ")

        sh(create_xcframework)
      end

      # Returns an array of -framework and -debug-symbol arguments for an xcarchive path
      def self.frameworks_symbols(path, xcframework, name)
        { bc_symbol_maps: [] }.tap do |frameworks_symbols|
          frameworks_symbols[:framework] = Dir.glob("#{path}/**/#{xcframework}.framework").first
          if frameworks_symbols[:framework].nil?
            FastlaneCore::UI.user_error!("▸ No #{xcframework}.framework found in #{path}")
          end
          frameworks_symbols[:dsym] = Dir.glob("#{path}/**/#{xcframework}.framework.dSYM").first
          Dir.glob("#{path}/**/BCSymbolMaps/*").each do |bc_symbol_map_path|
            bc_symbol_map = File.read(bc_symbol_map_path)
            next unless bc_symbol_map.include?("__swift_FORCE_LOAD_$_swiftFoundation_$_#{name}")

            frameworks_symbols[:bc_symbol_maps] << bc_symbol_map_path
          end
        end
      end

      # Generates an XCFramework without Library Evolution enabled (imitates Carthage)
      def self.generate_xcframework(frameworks_symbols, xcframework)
        FastlaneCore::UI.message "▸ Creating #{xcframework}.xcframework manually à la Carthage"

        frameworks_symbols.each do |sdk, details|
          destination = "#{xcframework}.xcframework/#{library_identifier(sdk)}"
          FileUtils.mkdir_p(["#{destination}/BCSymbolMaps", "#{destination}/dSYMs"])
          FileUtils.cp_r(details[:framework], destination)
          details[:bc_symbol_maps].each do |bc_symbol_map_path|
            FileUtils.cp(bc_symbol_map_path, "#{destination}/BCSymbolMaps")
          end
          FileUtils.cp_r(details[:dsym], "#{destination}/dSYMs") unless details[:dsym].nil?
        end
      end

      # Generates an XCFramework without Library Evolution enabled (imitates Carthage)
      def self.generate_xcframework_info_plist(frameworks_symbols, xcframework)
        FastlaneCore::UI.message "▸ Creating #{xcframework}.xcframework/Info.plist manually à la Carthage"

        info = {
          AvailableLibraries: frameworks_symbols.map do |sdk, details|
                                {}.tap do |dict|
                                  dict[:BitcodeSymbolMapsPath] = 'BCSymbolMaps' unless details[:bc_symbol_maps].empty?
                                  dict[:DebugSymbolsPath] = 'dSYMs'
                                  dict[:LibraryIdentifier] = library_identifier(sdk)
                                  dict[:LibraryPath] = "#{xcframework}.framework"
                                  dict[:SupportedArchitectures] = supported_architectures(sdk)
                                  dict[:SupportedPlatform] = sdk.downcase.delete_suffix('simulator')
                                  if library_identifier(sdk).end_with?('simulator')
                                    dict[:SupportedPlatformVariant] = 'simulator'
                                  end
                                end
                              end,
          CFBundlePackageType: 'XFWK',
          XCFrameworkFormatVersion: '1.0'
        }

        File.write("#{xcframework}.xcframework/Info.plist", info.to_plist)
      end

      # Returns the library identifier for a platform sdk
      def self.library_identifier(sdk)
        [
          sdk.delete_suffix('Simulator').downcase,
          supported_architectures(sdk).join('_'),
          sdk.end_with?('Simulator') ? 'simulator' : nil
        ].compact.join('-')
      end

      # Returns the destination value for a platform sdk
      def self.platform_destination(sdk)
        case sdk
        when 'carPlayOSSimulator' then 'generic/platform=carPlayOS Simulator'
        when 'iOSSimulator' then 'generic/platform=iOS Simulator'
        when 'iPadOSSimulator' then 'generic/platform=iPadOS Simulator'
        when 'macOSCatalyst' then 'generic/platform=macOS,variant=Mac Catalyst'
        when 'tvOSSimulator' then 'generic/platform=tvOS Simulator'
        when 'watchOSSimulator' then 'generic/platform=watchOS Simulator'
        else "generic/platform=#{sdk}"
        end
      end

      # Returns the scheme name for a given platform sdk
      def self.scheme(scheme, sdk)
        platform = case sdk
                   when 'carPlayOS', 'carPlayOSSimulator' then 'carPlayOS'
                   when 'iOS', 'iOSSimulator' then 'iOS'
                   when 'iPadOS', 'iPadOSSimulator' then 'iPadOS'
                   when 'macOSCatalyst' then 'Catalyst'
                   when 'macOS' then 'macOS'
                   when 'tvOS', 'tvOSSimulator' then 'tvOS'
                   when 'watchOS', 'watchOSSimulator' then 'watchOS'
                   end
        scheme.sub('{{platform}}', platform)
      end

      # Returns the sdks including simulators for a list of plaforms
      def self.sdks(platforms)
        [].tap do |sdks|
          platforms.each do |platform|
            sdks << platform
            case platform
            when 'carPlayOS' then sdks << 'carPlayOSSimulator'
            when 'iOS' then sdks << 'iOSSimulator'
            when 'iPadOS' then sdks << 'iPadOSSimulator'
            when 'tvOS' then sdks << 'tvOSSimulator'
            when 'watchOS' then sdks << 'watchOSSimulator'
            end
          end
        end
      end

      # Set the version and build number on an xcarchive framework
      def self.set_version_and_build_number(xcarchive_path, version, build_number)
        def self.set(entry, value, path)
          sh %(/usr/libexec/Plistbuddy -c "Set #{entry} #{value}" #{path})
        rescue FastlaneCore::Interface::FastlaneShellError => e
          sh %(/usr/libexec/Plistbuddy -c "Add #{entry} string #{value}" #{path})
        end

        Dir.glob("#{xcarchive_path}/Products/**/Info.plist").each do |path|
          unless version.nil?
            semver = version.scan(/(\d+\.)(\d+\.)(\*|\d+)(-[^+\s]+)?(\+\S+)?/).join
            FastlaneCore::UI.message %(▸ Setting version: "#{semver}")
            set('CFBundleShortVersionString', semver, path)
          end
          unless build_number.nil?
            FastlaneCore::UI.message %(▸ Setting build number: "#{build_number}")
            set('CFBundleVersion', build_number, path)
          end
        end
      end

      # Returns the supported architectures for a give platform sdk
      def self.supported_architectures(sdk)
        case sdk
        when 'carPlayOS' then ['undefined']
        when 'carPlayOSSimulator' then ['undefined']
        when 'iOS' then %w[arm64 armv7]
        when 'iOSSimulator' then %w[arm64 i386 x86_64]
        when 'iPadOS' then ['undefined']
        when 'iPadOSSimulator' then ['undefined']
        when 'macOSCatalyst' then ['undefined']
        when 'macOS' then %w[arm64 x86_64]
        when 'tvOS' then ['arm64']
        when 'tvOSSimulator' then %w[arm64 x86_64]
        when 'watchOS' then %w[arm64_32 armv7k]
        when 'watchOSSimulator' then %w[arm64 i386 x86_64]
        end
      end

      # Returns XCode arguments to pass in during the archive process
      def self.xcode_arguments(params)
        [
          'BITCODE_GENERATION_MODE=bitcode',
          'DEBUG_INFORMATION_FORMAT=dwarf-with-dsym',
          'ENABLE_BITCODE=YES',
          'SKIP_INSTALL=NO'
        ].tap do |args|
          args << 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES' if params[:enable_library_evolution]
          args << 'ENABLE_SK_ASSERT="-D ENABLE_SK_ASSERT"' if params[:enable_sk_assertions]
          params[:xcargs].each { |xcarg| args << xcarg }
        end.join(' ')
      end

      # #####################################################
      # # @!group Documentation
      # #####################################################

      def self.description
        'Creates an XCFramework with dSYMs and BCSymbolMaps'
      end

      def self.details
        'This script creates an XCFramework with dSYMs and BCSymbolMaps, and returns it as a zip archive.'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            description: 'The release build number',
            env_name: 'BUILD_NUMBER',
            key: :build_number,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            default_value: 'Release',
            description: 'The build configuration (Debug | Release) (default = Release)',
            key: :configuration,
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!('Please supply an argument (Debug | Release)') unless %w[Debug Release].include?(value)
            end
          ),
          FastlaneCore::ConfigItem.new(
            default_value: true,
            description: 'Whether to enable library evolution mode (default = true)',
            is_string: false,
            key: :enable_library_evolution,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            default_value: false,
            description: 'Whether to disable skAssertions (default = false)',
            is_string: false,
            key: :enable_sk_assertions,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The module name, if different than the scheme',
            key: :name,
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The platform variants to include in the XCFramework (e.g. "iOS,watchOS")',
            key: :platforms,
            optional: false,
            type: Array,
            verify_block: proc do |values|
              values.each do |value|
                unless %w[carPlayOS iOS iPadOS macOSCatalyst macOS tvOS watchOS].include?(value)
                  UI.user_error!('Please make sure the input is a directory')
                end
              end
            end
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The project containing the scheme to be built',
            key: :project,
            optional: true,
            verify_block: proc do |value|
                            path = File.expand_path(value.to_s)
                            UI.user_error!("Project file not found at path '#{path}'") unless File.exist?(path)
                            UI.user_error!('Project file invalid') unless File.directory?(path)
                            unless path.include?('.xcodeproj')
                              UI.user_error!('Project file is not a project file, must end with .xcodeproj')
                            end
                          end,
            conflicting_options: [:workspace],
            conflict_block: proc do |value|
                              UI.user_error!("You can only pass either a 'project' or a '#{value.key}', not both")
                            end
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The base name of the scheme to build. ' \
                         'Add "{{platform}}" placeholder for platform-based scheme names, e.g. "MyScheme-{{platform}}"',
            key: :scheme,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The release version',
            env_name: 'RELEASE_VERSION',
            key: :version,
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The workspace containing the scheme to be built',
            key: :workspace,
            optional: true,
            verify_block: proc do |value|
                            path = File.expand_path(value.to_s)
                            UI.user_error!("Workspace file not found at path '#{path}'") unless File.exist?(path)
                            UI.user_error!('Workspace file invalid') unless File.directory?(path)
                            unless path.include?('.xcworkspace')
                              UI.user_error!('Workspace file is not a workspace, must end with .xcworkspace')
                            end
                          end,
            conflicting_options: [:project],
            conflict_block: proc do |value|
                              UI.user_error!("You can only pass either a 'workspace' or a '#{value.key}', not both")
                            end
          ),
          FastlaneCore::ConfigItem.new(
            default_value: [],
            description: 'Any additional xcodebuild options',
            key: :xcargs,
            optional: true,
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The Xcode version toolchain to use when creating the XCFramework',
            env_name: 'XCODE_VERSION',
            key: :xcode_version,
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            description: 'The path where the XCFramework zip archive should be placed',
            key: :zip_destination,
            optional: false,
            type: String
          )
        ]
      end

      def self.output
        # Define the shared values you are going to provide
        # Example
        # [
        #   ['SMART_JAZZY_API_TABLE_CUSTOM_VALUE', 'A description of what this value contains']
        # ]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.authors
        ['SmartThings Client Team']
      end

      def self.is_supported?(platform)
        %i[ios mac].include?(platform)
      end
    end
  end
end
