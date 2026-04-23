# Эксплуатация

## Установка

`install.sh` по умолчанию устанавливает `mtg` `2.2.8`. Используйте `--mtg-version <VERSION>`
только если осознанно тестируете или фиксируете другую версию.

Обычный режим:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443
```

FakeTLS на одном сервере с nginx:

```bash
sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN> \
  --local-tls-proxy nginx --local-tls-port 4443
```

FakeTLS с выделенным IP или внешним TLS-сервером:

```bash
sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN>
```

## Статус

```bash
sudo systemctl status mtg --no-pager
ss -ltnp | grep -E ':(443|8443) '
```

## Диагностика

```bash
sudo mtg doctor /etc/mtg/config.toml
```

В FakeTLS-схеме на одном сервере проверка SNI-DNS может сообщить, что домен резолвится в
`127.0.0.1`. Это ожидаемо, если `/etc/hosts` намеренно указывает FakeTLS-домен на локальную
TLS-точку.
При этом проверки доступности Telegram DC и fronting-домена должны проходить.

## Логи

```bash
sudo journalctl -u mtg -f --no-pager
```

## Текущий secret

```bash
sudo cat /etc/mtg/secret
```

## Текущий config

```bash
sudo cat /etc/mtg/config.toml
```

## Перезапуск

```bash
sudo systemctl restart mtg
```

## Ротация secret

По умолчанию повторный запуск `install.sh` сохраняет существующий secret. Secret меняется
автоматически только если режим переключается между `standard` и `faketls`, меняется FakeTLS-домен,
secret отсутствует или передан `--rotate-secret`.

Явная ротация:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443 --rotate-secret
```

После ротации нужно раздать пользователям новую ссылку из вывода `install.sh`.

## Ссылка на прокси

`install.sh` печатает ссылку в конце установки. Если нужно собрать её вручную:

```bash
SECRET="$(sudo cat /etc/mtg/secret)"
IP="<IP>"
DOMAIN="<DOMAIN>" # необязательно; используйте для FakeTLS-ссылок
PORT="443"
SERVER="${DOMAIN:-$IP}"
echo "tg://proxy?server=${SERVER}&port=${PORT}&secret=${SECRET}"
echo "https://t.me/proxy?server=${SERVER}&port=${PORT}&secret=${SECRET}"
```

## Откат и резервные копии

Резервные копии systemd unit сохраняются здесь:

```text
/etc/systemd/system/mtg.service.bak.<timestamp>
```

Если использовалась локальная TLS-проверка, `uninstall.sh` также удаляет добавленный nginx listener
`127.0.0.1:443` и запись домена из `/etc/hosts`. Если state-файл потерян, uninstall пытается
восстановить FakeTLS-домен из существующего secret и убрать старые вспомогательные изменения.

Резервные копии создаются здесь:

```text
/etc/hosts.bak.<timestamp>
/etc/nginx/sites-enabled/<site>.bak.<timestamp>
```

## Удаление

```bash
sudo ./scripts/uninstall.sh --port 443
```

## Проверки перед релизом

```bash
bash -n scripts/install.sh
bash -n scripts/uninstall.sh
bash -n tests/install_test.sh
bash -n tests/uninstall_test.sh
bash tests/install_test.sh
bash tests/uninstall_test.sh
```

Для FakeTLS на одном сервере дополнительно проверьте публичный DNS. Если `mtg` слушает только IPv4,
hostname прокси не должен публиковать `AAAA`-запись:

```bash
dig +short A <DOMAIN>
dig +short AAAA <DOMAIN>
```
