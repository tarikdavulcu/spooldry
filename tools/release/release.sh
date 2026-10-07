#!/bin/bash
# Archives SpoolDry (Release, automatic signing) and uploads it to App Store Connect.
# Usage: tools/release/release.sh archive|upload
cd "$(dirname "$0")/../.."
ARCHIVE=/tmp/SpoolDry.xcarchive
case "$1" in
  archive) rm -rf $ARCHIVE; xcodebuild -project ios/SpoolDry.xcodeproj -scheme SpoolDry -configuration Release \
             -destination 'generic/platform=iOS' -archivePath $ARCHIVE -allowProvisioningUpdates archive ;;
  upload)  rm -rf /tmp/SpoolDryUpload; xcodebuild -exportArchive -archivePath $ARCHIVE \
             -exportOptionsPlist tools/release/ExportOptions.plist -exportPath /tmp/SpoolDryUpload -allowProvisioningUpdates ;;
esac
