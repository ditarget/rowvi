# Releasing Rowvi

You need `rcodesign`, an authenticated GitHub CLI, and the original Rowvi signing keys. The app signing key lives in `~/Library/Application Support/Rowvi/Signing`. The Sparkle key is stored in Keychain under the `rowvi` account. Keep secure backups of both keys. The release checks verify the signing certificate and Sparkle key against the values in the repository.

Update `CFBundleShortVersionString` and increment `CFBundleVersion` in [Resources/Info.plist](../Resources/Info.plist). Run the checks and build the release before committing the changes and pushing them to `main`. The commands below use version `0.1.7` as an example. Use the version from `CFBundleShortVersionString` for the tag and asset paths.

```sh
make check
make release
```

After pushing the release commit to `main`, tag it and publish the assets.

```sh
git tag v0.1.7
git push origin v0.1.7
gh release create v0.1.7 --repo ditarget/rowvi --verify-tag --latest --generate-notes \
  .build/releases/v0.1.7/Rowvi-v0.1.7.dmg \
  .build/releases/v0.1.7/Rowvi-v0.1.7.zip \
  .build/releases/v0.1.7/appcast.xml
```

`make release` signs the app with the existing certificate and sets the Sparkle feed URL. Publish all three files in the same release. Use the DMG for manual installation. Sparkle downloads the ZIP from the URL in the signed `appcast.xml`. Users can also install the ZIP manually.
