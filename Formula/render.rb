class Render < Formula
  desc "Kavi render app (macOS build)"
  homepage "https://github.com/kavisek/kavi-ios-render"
  head "ssh://git@github.com/kavisek/kavi-ios-render.git", branch: "main", using: :git

  depends_on :xcode => :build

  def install
    system "xcodebuild",
           "-project", "render/render.xcodeproj",
           "-scheme", "render",
           "-configuration", "Release",
           "-derivedDataPath", "build",
           "CODE_SIGNING_ALLOWED=NO",
           "build"

    app = Dir["build/Build/Products/Release/*.app"].first
    prefix.install app
    bin.write_exec_script prefix/File.basename(app)/"Contents/MacOS/render"
  end

  test do
    assert_predicate prefix/"render.app", :exist?
  end
end
