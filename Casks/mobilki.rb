cask "mobilki" do
  version "1.0.0"
  sha256 "bf551d20545b4efd99d73d9dcae916fad8cd06815e758ac6ac1a61cea523c6c5"

  url "https://github.com/testableapple/mobilki/releases/download/#{version}/Mobilki.dmg"
  name "Mobilki"
  desc "macOS menu bar app to manage iOS Simulators, Android Emulators, and real devices"
  homepage "https://github.com/testableapple/mobilki"

  depends_on macos: ">= :monterey"

  app "Mobilki.app"

  zap trash: [
    "~/Library/Preferences/com.testableapple.mobilki.plist",
    "~/Library/Caches/com.testableapple.mobilki",
    "~/Library/Application Support/com.testableapple.mobilki",
  ]
end
