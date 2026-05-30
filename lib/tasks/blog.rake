namespace :blog do
  desc "Build the Jekyll blog into public/blog"
  task :build do
    sh File.expand_path("../../bin/build-blog", __dir__)
  end
end
