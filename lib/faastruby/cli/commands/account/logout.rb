module FaaStRuby
  module Command
    module Account
      require 'faastruby/cli/commands/account/base_command'
      class Logout < AccountBaseCommand
        def initialize(args)
          @args = args
          parse_options
          @credentials_file = NewCredentials::CredentialsFile.new
          @credentials = @credentials_file.get
        end

        def run
          user = User.new(@credentials)
          unless user.has_credentials?
            puts "Logout successful."
            exit 0
          end
          user.logout(all: @options['all'])
          FaaStRuby::CLI.error(user.errors) if user&.errors.any?
          @credentials_file.clear
          puts "Logout successful."
        end

        def self.help
          "logout".light_cyan + " [--all]"
        end

        def usage
          puts "Usage: faastruby #{self.class.help}"
          puts %(
--all     # Logout from all machines
          )
        end

        private

        def parse_options
          @options = {}
          while @args.any?
            option = @args.shift
            case option
            when '-h', '--help', 'help'
              usage
              exit 0
            when '--all'
              @options['all'] = true
            else
              FaaStRuby::CLI.error(["Unknown argument: #{option}".red, usage], color: nil)
            end
          end
        end
      end
    end
  end
end
