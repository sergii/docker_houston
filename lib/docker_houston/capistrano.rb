# set(:branch, (ENV['tag'] || ENV['branch'] || ask(:branch, `git describe --abbrev=0 --tags`.strip)))

begin
  fetch(:repository)
  fetch(:application)
rescue IndexError => e
  puts "#{e.message} (ensure :application and :repository are set in deploy.rb)"
end

set :app_with_stage, ->{"#{fetch(:app_name)}"}

set :repo_url, ->{ fetch(:repository) } unless fetch(:repo_url)

set :release_dir, ->{Pathname.new("/home/deploy/dockerised_apps/#{fetch(:app_with_stage)}/current")}

set :shared_dir, ->{Pathname.new("/home/deploy/dockerised_apps/#{fetch(:app_with_stage)}/shared")}

set :log_dir, -> {Pathname.new("/home/deploy/dockerised_apps/logs/#{fetch(:app_with_stage)}")}

set :app_dir, ->{fetch(:release_dir).to_s.chomp('/current')}

# Override the release_path to be current_path as we
# have no notion of release folders
def exec_on_remote(command, message="Executing command on remote...", container_id='web')
  on roles :app do |server|
    ssh_cmd = "ssh -A -t #{server.user}@#{server.hostname}"
      puts "#{ssh_cmd} 'cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} run web #{command}"
      exec "#{ssh_cmd} 'cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} run web #{command}'"
  end
end

desc 'Run a rails console on remote'
task :console do
  exec_on_remote("bundle exec rails c", "Running console on remote...")
end

desc 'Run a bash terminal on remote'
task :bash do
  exec_on_remote("bash", "Running bash terminal on remote...")
end

namespace :docker do
  desc "deploy a git tag to a docker container"
  task :deploy do
    on roles :app do
      invoke 'deploy'
      invoke 'docker:setup_db'
      invoke 'docker:build_container'
      invoke 'docker:stop'
      invoke 'docker:start'
    end
  end

  desc 'relink docker databse'
  task :setup_db do
    on roles :app do
      docker_db = "#{fetch(:release_dir)}/config/database.yml.docker"
      if test "[ -f #{docker_db} ]"
        execute :cp, "#{docker_db} #{docker_db.chomp('.docker')}"
      end
    end
  end

  desc "build container"
  task :build_container do
    on roles :app do
      within fetch(:release_dir) do
        execute "cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} build web"
      end
    end
  end

  desc "precompile assets"
  task :precompile_assets do
    on roles :app do
      within fetch(:release_dir) do
        execute :echo, "precompiling assets..."
        execute "docker-compose  -p #{fetch(:app_with_stage)} run web bundle exec rake assets:precompile"
      end
    end
  end

  desc "start service"
  task :start do
    on roles :app do
      within fetch(:release_dir) do
        execute "cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} up -d"
      end
    end
  end

  desc "stop service"
  task :stop do
    on roles :app do
      within fetch(:release_dir) do
        execute "cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} kill" # kill the running containers
        execute "cd #{fetch(:release_dir)} && docker-compose -p #{fetch(:app_with_stage)} rm --force"
      end
    end
  end

  desc 'Run a bash console attached to the running docker application'
  task :bash do
    invoke 'bash'
  end

  desc 'Run a console attached to the running docker application'
  task :console do
    invoke 'console'
  end

  desc 'seed_fu'
  task :seed_fu do
    exec_on_remote("rake db:seed_fu", "Seeding database on remote...")
  end

  task :logs do
    execute "cd #{fetch(:log_dir)} && tail -f staging.log"
  end

end