class Render < Formula
  desc "Kavi render app (macOS build)"
  homepage "https://github.com/kavisek/kavi-ios-render"
  head "ssh://git@github.com/kavisek/kavi-ios-render.git", branch: "main", using: :git

  # Homebrew's own build sandbox can't compile this project: Xcode's Swift
  # macro plugin server (used by SwiftUI's #Preview macro) tries to sandbox
  # itself too, and macOS refuses that nested sandbox_apply. So instead of
  # building from the fetched source, this formula packages an app that was
  # already built outside Homebrew (see `make build-release` / `make install`).
  def install
    # Homebrew's build sandbox strips custom environment variables, so the
    # path to the prebuilt app is handed off via a file instead of $ENV.
    path_file = Pathname.new("/tmp/kavi-render-prebuilt-app-path")
    odie "#{path_file} not found (run `make install`, not `brew install` directly)" unless path_file.exist?

    app_path = Pathname.new(path_file.read.strip)
    odie "#{app_path} does not exist (run `make build-release` first)" unless app_path.exist?

    # `prefix.install` chmods the source in place, which the sandbox denies
    # for a path outside Homebrew's own temp/cache/Cellar; a plain recursive
    # copy avoids touching the source at all.
    system "cp", "-R", app_path, prefix/app_path.basename
    bin.write_exec_script prefix/app_path.basename/"Contents/MacOS/render"
  end

  test do
    assert_predicate prefix/"render.app", :exist?
  end
end
