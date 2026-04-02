# frozen_string_literal: true

module Baymax
  class ContextGatherer
    def initialize(repo_path: '.')
      @repo_path = repo_path
    end

    def gather(alert)
      revision = resolve_revision(alert.revision)
      {
        revision: revision,
        source_at_revision: nil,
        blame: nil,
        recent_commits: recent_commits(alert)
      }
    rescue StandardError => e
      warn "[baymax] Context gathering failed: #{e.message}. Proceeding with minimal context."
      { revision: 'HEAD', source_at_revision: nil, blame: nil, recent_commits: nil }
    end

    private

    def resolve_revision(revision)
      return 'HEAD' if revision.nil? || revision.to_s.empty?

      if revision_exists?(revision)
        revision
      else
        fetch_revision(revision) ? revision : 'HEAD'
      end
    end

    def revision_exists?(revision)
      system(
        'git', '-C', @repo_path,
        'cat-file', '-e', revision,
        out: File::NULL, err: File::NULL
      )
    end

    def fetch_revision(revision)
      system(
        'git', '-C', @repo_path,
        'fetch', 'origin', revision, '--depth=50',
        out: File::NULL, err: File::NULL
      )
    end

    def recent_commits(alert)
      rev = alert.revision.to_s.empty? ? 'HEAD' : alert.revision
      output = `git -C #{@repo_path} log --oneline -10 #{rev} 2>/dev/null`.strip
      output.empty? ? nil : output
    end
  end
end
