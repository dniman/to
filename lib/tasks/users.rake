namespace :users do
  desc "Create a user: bin/rails 'users:create[email, password]'"
  task :create, [ :email, :password ] => :environment do |_t, args|
    User.create!(email_address: args[:email], password: args[:password])
    puts "User #{args[:email]} created."
  end
end
