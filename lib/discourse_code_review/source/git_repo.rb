# frozen_string_literal: true

module DiscourseCodeReview::Source
  class GitRepo
    Commit =
      TypedData::TypedStruct.new(
        oid: String,
        message: String,
        author_name: String,
        author_email: String,
        author_time: DateTime,
        summary: String,
        diff: TypedData::OrNil[String],
      )

    def initialize(url, location, credentials: nil)
      @credentials = credentials

      begin
        @repo = Rugged::Repository.new(location)
      rescue Rugged::RepositoryError, Rugged::OSError
        @repo =
          Rugged::Repository.clone_at(
            url,
            location,
            bare: true,
            credentials: @credentials,
        )
      end
    end

    def n_before(ref, n)
      fetch
      commit = @repo.rev_parse(ref)

      n.times do
        break if commit.parents.empty?
        commit = commit.parents[0]
      end

      sanitize_string(commit.oid)
    end

    def trailers(ref)
      @repo
        .rev_parse(ref)
        .trailers
        .map { |trailer| trailer.map(&method(:sanitize_string)) }
    end

    def rev_parse(ref)
      sanitize_string(@repo.rev_parse_oid(ref))
    end

    def diff_excerpt(ref, path, position)
      lines =
        @repo
          .diff("#{ref}^", ref, paths: [path])
          .patch
          .force_encoding(Encoding::UTF_8)
          .split("\n")

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

    def contains?(a, b)
      a = @repo.rev_parse(a).oid
      b = @repo.rev_parse(b).oid

      @repo.merge_base(a, b) == b
    end

    def fetch
      @repo.remotes.each do |remote|
        @repo.fetch(remote, credentials: @credentials)
      end
    end

    def commit(ref)
      sanitize_commit(@repo.rev_parse(ref))
    end

    def commits_since(from, to)
      Enumerators::MapEnumerator.new(
        rugged_commits_since(from, to),
        &method(:sanitize_commit)
      )
    end

    def commit_oids_since(from, to)
      Enumerators::MapEnumerator.new(
        rugged_commits_since(from, to).each_oid,
        &method(:sanitize_string)
      )
    end

    private

    def rugged_commits_since(from, to)
      from = @repo.rev_parse(from)
      to = @repo.rev_parse(to)

      walker = Rugged::Walker.new(@repo)
      walker.push(to)
      walker.hide(from)
      walker
    end

    def sanitize_commit(commit)
      diff =
        if commit.parents.size == 1
          sanitize_string(commit.parents[0].diff(commit).patch)
        end

      Commit.new(
        oid: sanitize_string(commit.oid),
        message: sanitize_string(commit.message),
        author_name: sanitize_string(commit.author[:name]),
        author_email: sanitize_string(commit.author[:email]),
        author_time: commit.author[:time].to_datetime,
        summary: sanitize_string(commit.summary),
        diff: diff,
      )
    end

    def sanitize_string(value)
      value.force_encoding(Encoding::UTF_8)
    end
  end
end
