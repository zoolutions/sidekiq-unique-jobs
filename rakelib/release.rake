# frozen_string_literal: true

# The shared release task of the zoolutions release kit. This file is
# BYTE-IDENTICAL across the gems (canonical copy in docs-kit, see RELEASE_KIT.md;
# sync with `script/release-kit sync`): everything project-specific is derived
# from the one *.gemspec at the root, or lives in an optional hook task in the
# project's own Rakefile. Never edit it in a consuming repo.
#
#   rake release[1.2.3]         bump, commit, push main, publish the GitHub Release
#   rake release[1.3.0.rc1]     same, flagged --prerelease (alpha/beta/rc/pre)
#   rake release[pre]           re-release the current version as a prerelease
#   rake release[1.2.3,force]   delete + re-create an existing tag/release
#
# Publishing the GitHub Release fires .github/workflows/release.yml, which builds,
# signs (Sigstore) and pushes to RubyGems over OIDC trusted publishing. Never
# `gem push` by hand. `bin/release` is the interactive front door to this task.
#
# Optional hooks, defined in the project's Rakefile (both receive the version):
#
#   release:preflight[version]  runs first; abort here to stop before anything
#                               is touched (dash: the proxy image must exist)
#   release:prepare[version]    runs after the version bump; rewrite any other
#                               tracked file that should ship with it (daisyui:
#                               updated_at.rb). Changed tracked files are staged.
module ReleaseKit
  module_function

  def info(msg) = puts("\e[34m→\e[0m #{msg}")

  def success(msg) = puts("\e[32m✓\e[0m #{msg}")

  def skip(msg) = puts("\e[33m⊘\e[0m #{msg} \e[33m(skipped)\e[0m")

  def header(msg)
    rule = "─" * msg.length
    puts("\n\e[1;36m#{msg}\e[0m\n#{rule}")
  end

  def fail!(msg) = abort("\e[31mAborting: #{msg}\e[0m")

  def gemspec
    specs = Dir["*.gemspec"]
    fail!("expected exactly one *.gemspec, found #{specs.inspect}") unless specs.size == 1

    specs.first
  end

  # The lib/**/version.rb that holds the gem's current VERSION string.
  def version_file(current)
    files = Dir["lib/**/version.rb"].each_with_object([]) do |path, found|
      found << path if File.read(path).include?(%(VERSION = "#{current}"))
    end
    fail!("expected one lib/**/version.rb with VERSION = \"#{current}\", found #{files.inspect}") unless files.size == 1

    files.first
  end

  # Committed lockfiles only: an ignored Gemfile.lock (docs-kit's root) exists on
  # disk but must never be staged, or `git add` aborts mid-release.
  def tracked_lockfiles
    `git ls-files -- '*Gemfile.lock' '*.gemfile.lock'`.split("\n")
  end

  # The PATH spec ("    NAME (X.Y.Z)") and the CHECKSUMS entry ("  NAME (X.Y.Z)").
  # Exactly 2 or 4 spaces and a version that starts with a digit, so a dependency
  # line ("      NAME (>= 1.2, < 2)", 6 spaces) is never rewritten.
  def pin_pattern(name)
    /^( {2}| {4})#{Regexp.escape(name)} \((\d[^)]*)\)$/
  end

  # A lockfile that sources the gem locally (`gemspec` or `path:`) lists it as
  # "  NAME!" under DEPENDENCIES; that lock must carry a pin to bump.
  def sources_gem?(content, name)
    content.match?(/^  #{Regexp.escape(name)}!$/)
  end

  def pins(content, name)
    content.scan(pin_pattern(name)).map(&:last)
  end

  def bump_pins(content, name, version)
    content.gsub(pin_pattern(name)) { "#{Regexp.last_match(1)}#{name} (#{version})" }
  end

  # {lockfile => content} for every tracked lock that sources the gem. Called
  # BEFORE anything destructive (the force cleanup deletes a published release)
  # or any write (a half-bumped tree blocks the next run on the clean-tree
  # guard). A lock that sources the gem but has no pin means the format changed;
  # bumping past it would ship a stale lock the frozen `bundle install` rejects.
  def lockfiles_sourcing(name)
    locks = {}
    tracked_lockfiles.each do |lockfile|
      content = File.read(lockfile)
      next unless sources_gem?(content, name)

      fail!("#{lockfile} sources #{name} but has no `#{name} (X.Y.Z)` pin") if pins(content, name).empty?
      locks[lockfile] = content
    end
    locks
  end

  def git_clean? = `git status --porcelain --untracked-files=no`.strip.empty?

  def tag_exists?(tag) = system("git rev-parse -q --verify refs/tags/#{tag} >/dev/null 2>&1")

  def release_exists?(tag) = system("gh release view #{tag} >/dev/null 2>&1")

  # One release run: `ReleaseKit::Release.new("1.2.3", force: false).call`.
  class Release
    include Rake::FileUtilsExt

    def initialize(requested, force:)
      @force = force
      @gemspec = ReleaseKit.gemspec
      spec = Gem::Specification.load(@gemspec)
      @name = spec.name
      @current = spec.version.to_s
      @prerelease = requested == "pre" || requested.match?(/alpha|beta|rc|pre/)
      @version = requested == "pre" ? @current : requested
      @tag = "v#{@version}"
    end

    def call
      guard_main_and_clean
      announce
      hook("release:preflight")
      locks = kit.lockfiles_sourcing(@name)
      force_cleanup if @force
      bump_version
      hook("release:prepare")
      bump_lockfiles(locks)
      build
      commit
      push
      publish
    end

    private

    def kit = ReleaseKit

    def guard_main_and_clean
      branch = `git branch --show-current`.strip
      kit.fail!("must release from main (on #{branch})") unless branch == "main"
      dirty = `git status --porcelain`.strip
      kit.fail!("working directory is not clean\n#{dirty}") unless dirty.empty?
    end

    def announce
      @version_file = kit.version_file(@current)
      kit.header(@force ? "Release #{@name} #{@tag} (force)" : "Release #{@name} #{@tag}")
      kit.info "Current version: #{@current}  (#{@version_file})"
      kit.info "New version:     #{@version}"
      kit.info "Pre-release:     #{@prerelease}"
    end

    def hook(task_name)
      return unless Rake::Task.task_defined?(task_name)

      kit.header "Hook: #{task_name}"
      Rake::Task[task_name].invoke(@version)
    end

    def force_cleanup
      kit.header "Force cleanup"
      if kit.release_exists?(@tag)
        sh("gh release delete #{@tag} --yes --cleanup-tag")
        kit.success "Deleted release and remote tag #{@tag}"
      end
      sh("git tag -d #{@tag}") if kit.tag_exists?(@tag)
    end

    def bump_version
      kit.header "Version"
      return kit.skip("Version already #{@version}") if @version == @current

      content = File.read(@version_file).sub(/VERSION = ".*"/, %(VERSION = "#{@version}"))
      File.write(@version_file, content)
      kit.success "Updated #{@version_file}"
    end

    # Bump the path-gem pin in place instead of re-resolving (`bundle install` /
    # `bundle lock`): a re-resolve folds unrelated dependency jumps into the
    # release commit and fails on platform gems a Mac can't resolve for Linux.
    def bump_lockfiles(locks)
      kit.header "Lockfiles"
      kit.skip "No tracked lockfile sources #{@name}" if locks.empty?
      locks.each do |lockfile, content|
        next kit.skip("#{lockfile} already pins #{@version}") if kit.pins(content, @name).all?(@version)

        File.write(lockfile, kit.bump_pins(content, @name, @version))
        kit.success "Bumped #{@name} pin in #{lockfile}"
      end
    end

    def build
      kit.header "Build verification"
      sh("gem build #{@gemspec} --strict")
      sh("rm -f #{@name}-*.gem")
      kit.success "Gem builds cleanly"
    end

    # The tree was clean on entry, so every modified tracked file belongs to this
    # release: version.rb, the bumped lockfiles, whatever release:prepare wrote.
    def commit
      kit.header "Git commit"
      return kit.skip("Nothing to commit (already at #{@version})") if kit.git_clean?

      sh("git add --update")
      sh("git commit -m 'chore: bump version to #{@version}'")
      kit.success "Committed version bump"
    end

    def push
      kit.header "Git push"
      return kit.skip("origin/main already up to date") if `git rev-parse HEAD` == `git rev-parse origin/main`

      sh("git push origin main")
      kit.success "Pushed to origin/main"
    end

    def publish
      kit.header "GitHub Release"
      return kit.skip("Release #{@tag} already exists (pass force to re-create it)") if kit.release_exists?(@tag)

      target = kit.tag_exists?(@tag) ? "" : " --target main"
      prerelease = @prerelease ? " --prerelease" : ""
      sh("gh release create #{@tag} --generate-notes#{target}#{prerelease}")
      kit.success "Release #{@tag} is out. The Release workflow tests, builds, signs (Sigstore) " \
                  "and publishes it to RubyGems (trusted publishing)."
    end
  end
end

desc "Release a new version (rake release[1.2.3], release[pre], release[1.2.3,force])"
task :release, %i[version force] do |_t, args|
  ReleaseKit.fail!("usage: rake release[X.Y.Z] or rake release[X.Y.Z,force]") unless args[:version]
  ReleaseKit::Release.new(args[:version], force: args[:force].to_s.downcase == "force").call
end
