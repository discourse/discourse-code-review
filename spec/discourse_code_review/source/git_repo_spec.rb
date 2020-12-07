# frozen_string_literal: true

require 'rails_helper'

module DiscourseCodeReview
  describe Source::GitRepo do
    def with_tmpdir(&blk)
      path = "#{Pathname.new(Dir.tmpdir).realpath}/#{SecureRandom.hex}"
      begin
        blk.call(path)
      ensure
        FileUtils.rm_rf(path)
      end
    end

    describe '#default_branch' do
      it 'works with a different branch (not master or main)' do
        with_tmpdir do |origin_path|
          `git init #{origin_path}`

          Dir.chdir(origin_path) do
            File.write('a', "hello worlds\n")
            `git add a`
            `git commit -am 'first commit'`
            `git branch -m test-branch`
          end

          with_tmpdir do |checkout_path|
            git_repo = DiscourseCodeReview::Source::GitRepo.new(origin_path, checkout_path)
            expect(git_repo.default_branch).to eq("test-branch")
          end
        end
      end
    end
  end
end
