#!/bin/zsh
# Xcode Cloud runs this right after cloning, before building.
# Hindsight.xcodeproj isn't in git (it's generated from project.yml), so
# generate it here. Must live in ios/ci_scripts/, next to the project.
set -euo pipefail
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate
