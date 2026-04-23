# mtproxy-deploy

[English](README.md) | [Русский](README.ru.md)

Отдельный проект для установки и эксплуатации Telegram MTProxy на Ubuntu.

`mtproxy-deploy` решает одну задачу: установить, запустить и сопровождать MTProxy на VPS.

Используется [mtg](https://github.com/9seconds/mtg) — Go-реализация MTProxy, которая проксирует
настоящий TLS-хендшейк с реальным сертификатом. Это позволяет FakeTLS работать на всех клиентах
Telegram, включая Android.

## Что поддерживается

Проект умеет два режима:

- `standard`: обычный MTProxy на выбранном TCP-порту
- `faketls`: FakeTLS на `443` с доменом

Проект не управляет:

- пользователями и паролями
- квотами и биллингом
- сложной маршрутизацией нескольких сервисов через один `443`

## Требования

- Ubuntu 24.04 или похожая systemd-система
- root-доступ
- `curl`, `xxd`, `ufw` (устанавливаются автоматически через `install.sh`)
- для `faketls`:
  - домен должен смотреть на сервер
  - публичный `443/tcp` должен быть выделен под MTProxy
  - нужна TLS-точка для этого домена, которую `mtg` сможет проверить

`nginx` не является зависимостью проекта. Если у вас уже есть локальный HTTPS-сервис и вы хотите
переиспользовать его в схеме "один сервер", `mtproxy-deploy` может опционально пропатчить этот
локальный сервис.

## Быстрый старт

Обычный MTProxy на `8443`:

```bash
sudo ./scripts/install.sh \
  --mode standard \
  --host-ip 203.0.113.10 \
  --port 8443
```

FakeTLS на `443`:

```bash
sudo ./scripts/install.sh \
  --mode faketls \
  --host-ip 203.0.113.10 \
  --port 443 \
  --domain tg.example.com
```

Если вы осознанно строите схему "один сервер" и уже вынесли публичный сайт с `443`, можно включить
вспомогательную настройку для локальной TLS-проверки:

```bash
sudo ./scripts/install.sh \
  --mode faketls \
  --host-ip 203.0.113.10 \
  --port 443 \
  --domain tg.example.com \
  --local-tls-proxy nginx \
  --local-tls-port 4443
```

Это добавит:

- `127.0.0.1:443` в конфиг локального TLS-сервера
- `127.0.0.1 <domain>` в `/etc/hosts`

Это совместимость для установки на одном сервере, а не основная архитектура проекта.

## Что делает install.sh

1. Ставит зависимости: `curl`, `xxd`, `ufw`
2. Скачивает `mtg` `2.2.8` по умолчанию (автоматически определяет архитектуру; можно переопределить через `--mtg-version`)
3. Генерирует MTProxy secret через `mtg generate-secret`
4. По умолчанию сохраняет существующий secret (для ротации используйте `--rotate-secret`)
5. Записывает `/etc/mtg/config.toml`
6. Создаёт `/etc/systemd/system/mtg.service`
7. Перезапускает `mtg`, чтобы изменения бинарника, secret и config сразу применились
8. Открывает клиентский TCP-порт в `ufw`, если он есть
9. Печатает готовые Telegram-ссылки

## Структура

```text
scripts/install.sh          Установка или обновление MTProxy
scripts/uninstall.sh        Удаление установки
README.md                   Английское описание
README.ru.md                Русское описание
LICENSE                     MIT
docs/OPERATIONS.md          Эксплуатация и откат
docs/OPERATIONS.ru.md       Эксплуатация и откат на русском
docs/FAKETLS.md             Особенности FakeTLS
docs/FAKETLS.ru.md          Особенности FakeTLS на русском
tests/*.sh                  Shell-тесты для логики install/uninstall
```

## Формат ссылок

Обычный режим:

```text
tg://proxy?server=<IP>&port=<PORT>&secret=<SECRET>
https://t.me/proxy?server=<IP>&port=<PORT>&secret=<SECRET>
```

FakeTLS:

```text
tg://proxy?server=<DOMAIN>&port=443&secret=<SECRET>
https://t.me/proxy?server=<DOMAIN>&port=443&secret=<SECRET>
```

(Secret уже содержит домен — `mtg generate-secret --hex <domain>` генерирует полную строку
`ee<secret><domain_hex>`, которая вставляется в ссылку напрямую.)

## Примечания

- `mtg` проксирует реальный TLS-сертификат от домена. Именно поэтому FakeTLS работает и на iOS,
  и на Android.
- При FakeTLS не стоит пытаться спрятать несколько несвязанных сервисов за одним публичным `443`,
  если только вы не строите намеренно сложную TCP-маршрутизацию.
- Для FakeTLS на одном сервере публикуйте только `A`-запись для hostname прокси, если `mtg` не
  слушает IPv6. Публичная `AAAA`-запись на неиспользуемый IPv6 `443` может давать состояние
  "connected", но ломать реальный трафик.
- Держите MTProxy и SOCKS5 в отдельных репозиториях и сервисах.
