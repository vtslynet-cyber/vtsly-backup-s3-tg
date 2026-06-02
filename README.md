# VTSLY Backup — S3 & Telegram

```
██╗   ██╗████████╗███████╗██╗     ██╗   ██╗
██║   ██║╚══██╔══╝██╔════╝██║     ╚██╗ ██╔╝
██║   ██║   ██║   ███████╗██║      ╚████╔╝
╚██╗ ██╔╝   ██║   ╚════██║██║       ╚██╔╝
 ╚████╔╝    ██║   ███████║███████╗   ██║
  ╚═══╝     ╚═╝   ╚══════╝╚══════╝   ╚═╝
```

**Простой CLI-скрипт для автоматического резервного копирования директорий на Linux-сервере в S3-хранилище или в Telegram.**
Один файл, без зависимостей-фреймворков, понятное меню на цифрах, автоустановка всего необходимого, авто-добавление в cron. Интерфейс на **русском и английском**.

> A simple one-file Bash CLI to back up server directories to **S3** or **Telegram**, with auto-install, a digit-driven menu, automatic cron scheduling, and a **RU/EN** interface. (English section below.)

---

## 🇷🇺 Для чего это нужно

Если у тебя есть сервер (сайт, бот, база, конфиги) и ты хочешь, чтобы важные папки **регулярно и автоматически** копировались в надёжное место — этот скрипт делает всё за тебя:

- архивирует выбранную директорию в `.tar.gz`;
- отправляет архив в **S3** (AWS, Timeweb, Selectel, MinIO, Wasabi и любые S3-совместимые) **или в Telegram**;
- ставит задачу в **cron**, чтобы бэкап делался сам каждые N часов;
- сам устанавливает зависимости (`aws-cli`, `tar`, `cron`, `curl`), если их нет;
- хранит заданное число последних копий в S3, удаляя старые.

Подходит для тех, кто не хочет разбираться в настройке cron и aws-cli вручную — всё через простое меню.

## ✨ Возможности

- 📦 **Два назначения на выбор:** S3 или Telegram (выбор цифрой `1`/`2`).
- 🌍 **Два языка интерфейса:** русский / английский, переключается в любой момент.
- 🖱 **Управление цифрами:** всё меню и подтверждения — нажатием цифры (`1 = да`, `2 = нет`).
- ⏰ **Авто-cron:** задаёшь частоту в часах — скрипт сам строит расписание.
- 🧪 **Ручной/тестовый бэкап:** проверить настройку в один клик.
- 🗂 **Подменю бэкапа:** бэкап сейчас · бэкап другой папки разово · список архивов.
- 🔁 **Ротация:** хранит N последних копий в S3, старые чистит автоматически.
- 🛠 **Авто-установка зависимостей** под apt / dnf / yum / zypper / apk / pacman.
- 🔒 **Безопасно:** ключи вводятся скрыто, конфиг хранится с правами `600`, в репозитории секретов нет.

## 📋 Требования

- Linux-сервер с `bash` и правами `root` (или `sudo`).
- Для S3 — доступ в интернет (для установки `aws-cli`).
- Для Telegram — бот (создаётся у [@BotFather](https://t.me/BotFather)) и `chat_id` (узнать через [@userinfobot](https://t.me/userinfobot)).

## 🚀 Установка и запуск

```bash
# 1. Скачать скрипт на сервер
wget https://raw.githubusercontent.com/vtslynet-cyber/vtsly-backup-s3-tg/main/vtsly-backup.sh
# или
curl -O https://raw.githubusercontent.com/vtslynet-cyber/vtsly-backup-s3-tg/main/vtsly-backup.sh

# 2. Запустить мастер настройки (поставит зависимости, спросит настройки, добавит в cron)
sudo bash vtsly-backup.sh setup
```

После установки скрипт доступен как команда `vtsly-backup`:

```bash
vtsly-backup            # открыть меню (всё на цифрах)
```

## 🧭 Меню

```
1) Настроить бэкап (мастер)
2) Сделать бэкап — сейчас, другая папка, список архивов
3) Проверить соединение (S3/Telegram)
4) Настроить/обновить cron
5) Удалить cron
6) Статус и настройки
7) Показать лог
8) Сменить язык / Change language
0) Выход
```

## ⌨️ Команды (без меню)

| Команда | Что делает |
|---|---|
| `vtsly-backup setup` | Мастер настройки (зависимости + конфиг + cron) |
| `vtsly-backup menu` | Интерактивное меню |
| `vtsly-backup backup [tag]` | Сделать бэкап сейчас |
| `vtsly-backup test` | Тестовый бэкап |
| `vtsly-backup check` | Проверить соединение (S3 или Telegram) |
| `vtsly-backup cron` | Настроить/обновить задачу cron |
| `vtsly-backup cron-remove` | Удалить задачу cron |
| `vtsly-backup status` | Показать настройки и состояние cron |
| `vtsly-backup install-deps` | Только установить зависимости |
| `vtsly-backup lang` | Сменить язык (RU/EN) |
| `vtsly-backup log` | Показать лог |
| `vtsly-backup --help` | Справка |

## ⚙️ Как это работает

- **Имя архива:** `<хост>_<папка>_<дата-время>_<тег>.tar.gz`
  Пример: `web01_mysite_20260602-030000_auto.tar.gz`
- **Путь в S3:** `s3://<бакет>/<префикс>/<имя_архива>` (префикс по умолчанию `BACKUP/<IP сервера>`).
- **Telegram:** архив приходит в чат файлом с подписью (хост, папка, дата). ⚠️ Лимит бота — **50 МБ** на файл; для больших бэкапов используй S3.
- **Локально:** временные архивы лежат в `/var/backups/vtsly`.

## 📁 Файлы на сервере

| Путь | Назначение |
|---|---|
| `/usr/local/bin/vtsly-backup` | Установленная команда |
| `/etc/vtsly/vtsly.conf` | Конфигурация (права `600`, содержит ключи) |
| `/var/log/vtsly.log` | Лог работы |
| `/var/backups/vtsly` | Локальные архивы |

## 🔐 Безопасность

- Ключи S3 и токен Telegram **не хранятся в скрипте** — их вводит пользователь при настройке.
- Конфиг с секретами создаётся с правами `600` (только владелец-root).
- Секреты в меню маскируются (`****1234`).

## 🤝 Вклад

Issues и pull request'ы приветствуются.

## 📄 Лицензия

MIT — используй свободно.

---

## 🇬🇧 English

**VTSLY Backup** is a single-file Bash CLI that backs up a chosen directory on your Linux server to **S3** (AWS / Timeweb / Selectel / MinIO / Wasabi / any S3-compatible) or to **Telegram**.

### Features
- Two destinations: **S3** or **Telegram** (pick with `1`/`2`).
- **RU/EN** interface, switchable anytime.
- Digit-driven menu and confirmations (`1 = yes`, `2 = no`).
- **Automatic cron** scheduling by hours.
- Manual/test backup, backup submenu (now / another folder / list archives).
- Retention: keeps the last *N* copies in S3, auto-removes older ones.
- Auto-installs dependencies (apt / dnf / yum / zypper / apk / pacman).
- Secure: keys entered hidden, config stored `600`, no secrets in the repo.

### Quick start
```bash
curl -O https://raw.githubusercontent.com/vtslynet-cyber/vtsly-backup-s3-tg/main/vtsly-backup.sh
sudo bash vtsly-backup.sh setup
```
Then just run `vtsly-backup` to open the menu.

### Notes
- Archive name: `<host>_<folder>_<datetime>_<tag>.tar.gz`
- S3 path: `s3://<bucket>/<prefix>/<archive>` (default prefix `BACKUP/<server IP>`).
- Telegram bot file limit is **50 MB** — use S3 for larger backups.
- Config: `/etc/vtsly/vtsly.conf` (`600`) · Log: `/var/log/vtsly.log` · Local archives: `/var/backups/vtsly`.

**License:** MIT
