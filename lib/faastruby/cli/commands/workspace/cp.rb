module FaaStRuby
  module Command
    module Workspace
      require 'tmpdir'
      require 'tempfile'
      require 'uri'
      # require 'faastruby/cli/commands/workspace/base_command'
      require 'faastruby/cli/package'
      require 'faastruby/cli/new_credentials'
      class CP < BaseCommand
        def initialize(args)
          @args = args
          help
          @source_file = @args.shift
          @workspace_name, @relative_path = @args.shift.split(':')
          validate_command
          @package_file = Tempfile.new('package')
          @tmpdir = Dir.mktmpdir("package")
          # FaaStRuby::CLI.error(@missing_args, color: nil) if missing_args.any?
          load_credentials
        end

        def run
          FaaStRuby::CLI.error("You can't upload static files larger than 5MB. If you need to upload large files, please reach out to us on Slack at https://faastruby.io/slack") if source_file_too_big?
          destination_url = URI.escape("#{FaaStRuby.workspace_host_for(@workspace_name)}/#{@relative_path}")
          # spinner = say("[#{@source_file}] Copying file to '#{destination_url}'...", quiet: true)
          workspace = FaaStRuby::Workspace.new(name: @workspace_name)
          package = build_package
          workspace.upload_file(package, relative_path: @relative_path)
          FaaStRuby::CLI.error(workspace.errors) if workspace.errors.any?
          # spinner.stop("Done!")
          puts "* [#{@source_file}] Upload OK".green
          puts "* [#{@source_file}] URL: #{destination_url}".green
        ensure
          FileUtils.remove_entry @tmpdir
          @package_file.unlink
        end

        def source_file_too_big?
          File.size(@source_file) > 5242880 # That's 5MB
        end

        def build_package
          FileUtils.cp @source_file, @tmpdir
          output_file = @package_file.path
          FaaStRuby::Package.new(@tmpdir, output_file).build
          @package_file.close
          output_file
        end

        def self.help
          "cp SOURCE_FILE WORKSPACE_NAME:/DESTINATION/PATH"
        end

        def usage
          puts "\n# Deploy static file SOURCE_FILE to workspace path /DESTINATION/PATH.\n"
          puts "\nUsage: faastruby #{self.class.help}\n\n"
        end

        private

        def validate_command
          validate_source_file
          validate_workspace_name
          validate_relative_path
        end

        def validate_relative_path
          @relative_path.sub!(/^\//, '')
          FaaStRuby::CLI.error(["Invalid destination path: #{@relative_path}".red, "The destination path must have at least one character and can only contain letters, numbers, -, _, . and /."], color: nil) unless @relative_path&.match(/#{FUNCTION_NAME_REGEX}/)
        end

        def validate_workspace_name
          FaaStRuby::CLI.error(["Invalid workspace name: #{@workspace_name}".red, "The workspace name must have between 3 and 15 characters, and can only have letters, numbers and dashes."], color: nil) unless @workspace_name&.match(/#{WORKSPACE_NAME_REGEX}/)
          true
        end

        def validate_source_file
          FaaStRuby::CLI.error(["You must specify source file, workspace and destination path for the file.".red, usage], color: nil) unless (@source_file && @source_file != '')
          FaaStRuby::CLI.error("No such file: '#{@source_file}'") unless File.exists?(@source_file)
          FaaStRuby::CLI.error("You can only 'cp' files, not directories.") unless File.file?(@source_file)
          true
        end
      end
    end
  end
end
