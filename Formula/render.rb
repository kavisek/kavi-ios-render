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
    prebuilt_app = ENV["RENDER_PREBUILT_APP"]
    odie "Set $RENDER_PREBUILT_APP to a locally built render.app (run `make build-release` first)" if prebuilt_app.blank?

    app_path = Pathname.new(prebuilt_app)
    odie "#{app_path} does not exist" unless app_path.exist?

    prefix.install app_path
    bin.write_exec_script prefix/app_path.basename/"Contents/MacOS/render"
  end

  test do
    assert_predicate prefix/"render.app", :exist?
  end
end
