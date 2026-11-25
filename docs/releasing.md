# Публикация релиза Rowvi

Для выпуска нужны `rcodesign`, авторизованный GitHub CLI и оригинальные ключи Rowvi. Ключ подписи приложения хранится в `~/Library/Application Support/Rowvi/Signing`, ключ Sparkle - в Связке ключей под аккаунтом `rowvi`. Сделайте защищённые резервные копии обоих ключей. Проверка релиза сверяет сертификат и ключ Sparkle со значениями в репозитории.

Увеличьте `CFBundleShortVersionString` и `CFBundleVersion` в [Resources/Info.plist](../Resources/Info.plist), сделайте коммит и отправьте его в `main`. В примере используется версия `0.1.7`. Подставьте номер выпуска из `CFBundleShortVersionString`.

```sh
make check
make release
git tag v0.1.7
git push origin v0.1.7
gh release create v0.1.7 --repo ditarget/rowvi --verify-tag --latest --generate-notes \
  .build/releases/v0.1.7/Rowvi-v0.1.7.dmg \
  .build/releases/v0.1.7/Rowvi-v0.1.7.zip \
  .build/releases/v0.1.7/appcast.xml
```

`make release` подписывает приложение постоянным сертификатом и добавляет адрес списка обновлений Sparkle. Публикуйте все три файла в одном релизе. DMG предназначен для ручной установки, а Sparkle скачивает ZIP по ссылке из подписанного `appcast.xml`. ZIP также можно установить вручную.
