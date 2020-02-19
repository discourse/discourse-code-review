# frozen_string_literal: true

module DiscourseCodeReview
  class GitRepo
    def initialize(url, location)
      begin
        @repo = Rugged::Repository.new(location)
      rescue Rugged::RepositoryError, Rugged::OSError
        @repo = Rugged::Repository.clone_at(url, location, bare: true)
      end
    end

    def n_before(ref, n)
      fetch
      commit = @repo.rev_parse(ref)

      n.times do
        break if commit.parents.empty?
        commit = commit.parents[0]
      end

      commit.oid
    end

    def commit(ref)
      @repo.rev_parse(ref)
    end

    def rev_parse(ref)
      @repo.rev_parse_oid(ref)
    end

    def commits_since(from, to)
      from = @repo.rev_parse(from)
      to = @repo.rev_parse(to)

      walker = Rugged::Walker.new(@repo)
      walker.push(to)
      walker.hide(from)
      walker
    end

    def diff_excerpt(ref, path, position)
      lines = @repo.diff("#{ref}^", ref, paths: [path]).patch.split("\n")
      # -1 since lines use 1-based indexing
      # 5 lines in the preamble
      # 3 lines of context before and after
      # start and finish are inclusive
      start = [position - 1 + 5 - 3, 5].max
      finish = position - 1 + 5 + 3
      lines[start..finish].join("\n")
    end

    def commit_hash_valid?(ref)
      begin
        obj = @repo.rev_parse(ref)
      rescue Rugged::ReferenceError
        false
      end

      obj.kind_of?(Rugged::Commit)
    end

    def master_contains?(ref)
      oid = @repo.rev_parse(ref).oid
      @repo.merge_base('origin/master', oid) == oid
    end

    def fetch
      @repo.remotes.each do |remote|
        @repo.fetch(remote)
      end
    end
  end
end
