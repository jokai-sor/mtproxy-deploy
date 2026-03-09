# mtproxy-deploy

Отдельный проект для установки и эксплуатации Telegram MTProxy на Ubuntu.

`mtproxy-deploy` решает одну задачу: чисто собрать, установить, запустить и сопровождать MTProxy на VPS.

## Что поддерживается

Проект умеет два режима:

- `standard`: обычный MTProxy на выбранном TCP-порту
- `faketls`: TLS transport / FakeTLS на `443` с доменом

Проект не управляет:

- пользователями и паролями
- квотами и биллингом
- сложной маршрутизацией нескольких сервисов через один `443`

## Требования

- Ubuntu 24.04 или похожая systemd-система
- root-доступ
- `ufw`, если нужно автоматическое открытие порта
- для `faketls`:
  - домен должен смотреть на сервер
  - локальный HTTPS endpoint должен уметь отвечать за этот домен
  - публичный `443/tcp` должен быть выделен под MTProxy

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

Если публичный сайт уже вынесен с `443`, а локально HTTPS доступен на другом порту, можно включить вспомогательную локальную TLS-проверку:

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

Используйте это только если понимаете, что именно меняется.

## Что делает install.sh

1. Ставит build-зависимости
2. Клонирует официальный upstream MTProxy
3. Применяет 2 совместимых патча, которые понадобились на этом Ubuntu-окружении:
- `-fcommon` в `Makefile`
- патч `common/pid.c` из-за предположения upstream о 16-битном PID
4. Загружает `proxy-secret` и `proxy-multi.conf`
5. Генерирует MTProxy secret
6. Создает `/etc/systemd/system/mtproxy.service`
7. Открывает клиентский TCP-порт в `ufw`, если он есть
8. Печатает готовые Telegram-ссылки

## Структура

```text
scripts/install.sh          Установка или обновление MTProxy
scripts/uninstall.sh        Удаление deployment
README.md                   Английское описание
README.ru.md                Русское описание
LICENSE                     MIT
/docs/OPERATIONS.md         Эксплуатация и откат
/docs/FAKETLS.md            Особенности FakeTLS
```

## Формат ссылок

Обычный режим:

```text
tg://proxy?server=<IP>&port=<PORT>&secret=<SECRET>
https://t.me/proxy?server=<IP>&port=<PORT>&secret=<SECRET>
```

FakeTLS:

```text
tg://proxy?server=<IP>&port=443&secret=ee<SECRET><DOMAIN_HEX>
https://t.me/proxy?server=<IP>&port=443&secret=ee<SECRET><DOMAIN_HEX>
```
