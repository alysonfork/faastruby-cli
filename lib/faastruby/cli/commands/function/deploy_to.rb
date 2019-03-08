module FaaStRuby
  module Command
    module Function
      require 'faastruby/cli/commands/function/base_command'
      require 'faastruby/cli/new_credentials'
      class DeployTo < FunctionBaseCommand
        def initialize(args)
          @args = args
          help
          @missing_args = []
          FaaStRuby::CLI.error(@missing_args, color: nil) if missing_args.any?
          @workspace_name = @args.shift
          parse_options
          load_yaml
          @yaml_config['before_build'] ||= []
          @function_name = @yaml_config['name']
          unless @yaml_config['serve_static']
            @options['root_to'] = @function_name if @options['is_root']
            @options['catch_all'] = @function_name if @options['is_catch_all']
            # @abort_when_tests_fail = true #@yaml_config['abort_deploy_when_tests_fail']
          end
          load_credentials
          @package_file = Tempfile.new('package')
        end

        def ruby_runtime?
          @yaml_config['runtime'].nil? || @yaml_config['runtime'].match(/^ruby/)
        end

        def crystal_runtime?
          return false if @yaml_config['runtime'].nil?
          @yaml_config['runtime'].match(/^crystal/)
        end

        def runtime_name
          return 'Ruby' if ruby_runtime?
          return 'Crystal' if crystal_runtime?
          return 'Ruby'
        end

        def run
          create_or_use_workspace
          if @yaml_config['serve_static']
            package_file_name = build_package
            spinner = say("[#{@function_name}] Deploying static files '#{@function_name}' to workspace '#{@workspace_name}'...", quiet: @options['quiet'])
            workspace = FaaStRuby::Workspace.new(name: @workspace_name).deploy(package_file_name)
          else
            if ruby_runtime?
              FaaStRuby::CLI.error('Please fix the problems above and try again') unless bundle_install
            end
            if crystal_runtime?
              FaaStRuby::CLI.error('Please fix the problems above and try again') unless shards_install
            end
            FaaStRuby::CLI.error("[#{@function_name}] Deploy aborted because 'test_command' exited non-zero.") unless run_tests
            package_file_name = build_package
            spinner = say("[#{@function_name}] Deploying #{runtime_name} function '#{@function_name}' to workspace '#{@workspace_name}'...", quiet: @options['quiet'])
            workspace = FaaStRuby::Workspace.new(name: @workspace_name).deploy(package_file_name, root_to: @options['root_to'], catch_all: @options['catch_all'], context: @options['context'])
          end
          if workspace.errors.any?
            puts ' Failed :(' unless spinner&.stop(' Failed :(')
            @package_file.unlink
            FaaStRuby::CLI.error(workspace.errors)
          end
          spinner.stop(' Done!') unless @options['quiet']
          @package_file.unlink
          puts "* [#{@function_name}] Deploy OK".green
          unless @yaml_config['serve_static']
            puts "* [#{@function_name}] Workspace: #{@workspace_name}".green
            puts "* [#{@function_name}] Endpoint: #{FaaStRuby.workspace_host_for(@workspace_name)}/#{@function_name unless @options['root_to']}".green
          end
          puts '---'
          exit 0
        end

        def self.help
          "deploy-to WORKSPACE_NAME [ARGS]"
        end

        def usage
          puts "\nUsage: faastruby #{self.class.help}"
          puts %(
-f,--function PATH/TO/FUNCTION     # Specify the directory where the function is.
--context DATA                     # The data to be stored as context in the cloud,
                                   # accessible via 'event.context' from within your function.
--set-root                         # Set the function as the root route of the workspace/
--set-catch-all                    # Set the function as the catch-all route of the workspace.
--dont-create-workspace            # Don't try to create the workspace if it doesn't exist.
          )
        end

        private

        def create_or_use_workspace
          return true if @options['dont_create_workspace']
          require 'faastruby/cli/commands/workspace/create'
          # puts "[#{@function_name}] Attemping to create workspace '#{@workspace_name}'"
          cmd = FaaStRuby::Command::Workspace::Create.new([@workspace_name])
          result = cmd.run(create_directory: false, exit_on_error: false)
          if result
            # Give a little bit of time after creating the workspace
            # for consistency. This is temporary until the API gets patched.
            spinner = say("[#{@function_name}] Waiting for the workspace '#{@workspace_name}' to be ready...", quiet: @options['quiet'])
            sleep 2
            puts ' Done!' unless spinner&.stop(' Done!')
          end
        end

        def shards_install
          return true unless File.file?('shard.yml')
          puts "[#{@function_name}] [build] Verifying dependencies"
          system('shards check') || system('shards install')
        end

        def bundle_install
          return true unless File.file?('Gemfile')
          puts "[#{@function_name}] [build] Verifying dependencies"
          system('bundle check') || system('bundle install')
        end

        def missing_args
          if @args.empty?
            @missing_args << "Missing argument: WORKSPACE_NAME".red
            @missing_args << usage
          end
          FaaStRuby::CLI.error(["'#{@args.first}' is not a valid workspace name.".red, usage], color: nil) if @args.first =~ /^-.*/
          @missing_args
        end

        def run_tests
          return true unless @yaml_config['test_command']
          require 'faastruby/cli/commands/function/test'
          FaaStRuby::Command::Function::Test.new(true).run(do_not_exit: true)
        end

        def build_package
          source = '.'
          output_file = @package_file.path
          if @yaml_config['before_build'].any?
            spinner = say("[#{@function_name}] Running 'before_build' tasks...", quiet: @options['quiet'])
            @yaml_config['before_build']&.each do |command|
              puts `#{command}`
            end
            puts ' Done!' unless spinner&.stop(' Done!')
          end
          require 'faastruby/cli/commands/function/build'
          FaaStRuby::Command::Function::Build.build(source, output_file, @function_name, true)
          @package_file.close
          output_file
        end

        def parse_options
          @options = {}
          while @args.any?
            option = @args.shift
            case option
            when '-f', '--function'
              Dir.chdir @args.shift
            when '--context'
              @options['context'] = @args.shift
            when '--quiet', '-q'
              @options['quiet'] = true
            when '--set-root'
              @options['is_root'] = true
            when '--set-catch-all'
              @options['is_catch_all'] = true
            when '--dont-create-workspace'
              @options['dont_create_workspace'] = true
            else
              FaaStRuby::CLI.error("Unknown argument: #{option}")
            end
          end
        end

      end
    end
  end
end
