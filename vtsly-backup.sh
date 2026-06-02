#!/usr/bin/env bash
#
# ██╗   ██╗████████╗███████╗██╗     ██╗   ██╗
# ██║   ██║╚══██╔══╝██╔════╝██║     ╚██╗ ██╔╝
# ██║   ██║   ██║   ███████╗██║      ╚████╔╝
# ╚██╗ ██╔╝   ██║   ╚════██║██║       ╚██╔╝
#  ╚████╔╝    ██║   ███████║███████╗   ██║
#   ╚═══╝     ╚═╝   ╚══════╝╚══════╝   ╚═╝
#
#  VTSLY — простой бэкап в S3 / Telegram (CLI)
#  Установка одной командой, настройка через CLI, авто-cron.
#  VTSLY — simple backup to S3 / Telegram (CLI)
# ---------------------------------------------------------------

set -uo pipefail

# ====================== КОНСТАНТЫ / ПУТИ =======================
VTSLY_VERSION="2.0.0"
VTSLY_HOME="/etc/vtsly"
VTSLY_CONF="${VTSLY_HOME}/vtsly.conf"
VTSLY_LOG="/var/log/vtsly.log"
VTSLY_BACKUP_DIR_LOCAL="/var/backups/vtsly"
VTSLY_SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
VTSLY_BIN="/usr/local/bin/vtsly-backup"
CRON_TAG="# VTSLY-BACKUP"
TG_LIMIT_BYTES=$((50 * 1024 * 1024))   # лимит файла Telegram-бота: 50 МБ

# ========================== ЦВЕТА ==============================
if [ -t 1 ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
  C_RED="\033[31m"; C_GRN="\033[32m"; C_YLW="\033[33m"
  C_BLU="\033[34m"; C_CYN="\033[36m"; C_MAG="\033[35m"
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_CYN=""; C_MAG=""
fi

# ========================== ДЕФОЛТЫ ============================
DEFAULT_LANG="ru"            # язык интерфейса: ru | en
DEFAULT_BACKUP_TARGET="s3"   # куда бэкапить: s3 | tg (Telegram)
DEFAULT_S3_ENABLED="true"
DEFAULT_S3_ENDPOINT=""
DEFAULT_S3_REGION="us-east-1"
DEFAULT_S3_BUCKET=""
DEFAULT_S3_PREFIX=""         # авто: BACKUP/<IP сервера>
DEFAULT_S3_ACCESS_KEY=""
DEFAULT_S3_SECRET_KEY=""
# --- Telegram ---
DEFAULT_TG_BOT_TOKEN=""      # токен бота от @BotFather
DEFAULT_TG_CHAT_ID=""        # id чата/канала (узнать через @userinfobot)
# --- Общее ---
DEFAULT_BACKUP_DIR="/var/www"
DEFAULT_BACKUP_EVERY_HOURS="24"
DEFAULT_RETENTION="7"        # сколько последних бэкапов хранить в S3 (0 = не чистить)

VTSLY_LANG="${VTSLY_LANG:-$DEFAULT_LANG}"

# ====================== ЛОКАЛИЗАЦИЯ (i18n) =====================
# t <ключ> [аргументы...] — печатает переведённую строку (printf-формат с %s).
t() {
  local k="$1"; shift
  local f
  case "${VTSLY_LANG:-ru}::$k" in
    # --- общее / служебное ---
    ru::banner_sub)   f="Бэкап в S3 / Telegram · v%s" ;;     en::banner_sub)   f="Backup to S3 / Telegram · v%s" ;;
    ru::need_root)    f="Запусти с правами root:  sudo %s" ;; en::need_root)    f="Run as root:  sudo %s" ;;
    ru::yn_bad)       f="Не понял ответ. Введи 1 (да) или 2 (нет)." ;; en::yn_bad) f="Didn't get that. Enter 1 (yes) or 2 (no)." ;;
    ru::yn_hint_yes)  f="1=да / 2=нет, Enter=да" ;;  en::yn_hint_yes) f="1=yes / 2=no, Enter=yes" ;;
    ru::yn_hint_no)   f="1=да / 2=нет, Enter=нет" ;; en::yn_hint_no)  f="1=yes / 2=no, Enter=no" ;;
    ru::req_empty)    f="Это поле нельзя оставить пустым." ;; en::req_empty)    f="This field cannot be empty." ;;
    ru::secret_keep)  f="оставь пустым — не менять" ;;        en::secret_keep)  f="leave empty — keep current" ;;
    ru::need_int)     f="Нужно целое число." ;;              en::need_int)     f="Please enter a whole number." ;;
    ru::tgt_where)    f="Куда отправлять бэкап?" ;;          en::tgt_where)    f="Where to send the backup?" ;;
    ru::tgt_s3)       f="S3-хранилище" ;;                    en::tgt_s3)       f="S3 storage" ;;
    ru::tgt_tg)       f="Telegram (бот)" ;;                  en::tgt_tg)       f="Telegram (bot)" ;;
    ru::choice)       f="Выбор" ;;                           en::choice)       f="Choice" ;;
    ru::tgt_bad)      f="Введи 1 (S3) или 2 (Telegram)." ;;  en::tgt_bad)      f="Enter 1 (S3) or 2 (Telegram)." ;;
    *::lang_q)        f="Язык / Language:" ;;
    *::lang_bad)      f="1 = Русский, 2 = English" ;;
    # --- зависимости ---
    ru::aws_have)     f="aws-cli уже установлен." ;;         en::aws_have)     f="aws-cli is already installed." ;;
    ru::aws_inst)     f="Устанавливаю aws-cli..." ;;        en::aws_inst)     f="Installing aws-cli..." ;;
    ru::aws_pkg)      f="aws-cli установлен (пакет)." ;;     en::aws_pkg)      f="aws-cli installed (package)." ;;
    ru::arch_unk)     f="Неизвестная архитектура %s, пробую x86_64" ;; en::arch_unk) f="Unknown architecture %s, trying x86_64" ;;
    ru::aws_v2ok)     f="aws-cli v2 установлен." ;;          en::aws_v2ok)     f="aws-cli v2 installed." ;;
    ru::aws_v2fail)   f="Не удалось установить aws-cli v2." ;; en::aws_v2fail) f="Failed to install aws-cli v2." ;;
    ru::deps_check)   f="Проверяю зависимости..." ;;        en::deps_check)   f="Checking dependencies..." ;;
    ru::deps_add)     f="Доустанавливаю: %s" ;;             en::deps_add)     f="Installing: %s" ;;
    ru::deps_partial) f="Часть пакетов могла не установиться — проверь вручную." ;; en::deps_partial) f="Some packages may have failed — check manually." ;;
    ru::aws_optional) f="aws-cli не установлен (нужен только для S3; для Telegram не требуется)." ;; en::aws_optional) f="aws-cli not installed (needed only for S3; not required for Telegram)." ;;
    ru::deps_ready)   f="Все зависимости готовы." ;;        en::deps_ready)   f="All dependencies are ready." ;;
    # --- конфиг / мастер ---
    ru::cfg_saved)    f="Конфиг сохранён: %s" ;;            en::cfg_saved)    f="Config saved: %s" ;;
    ru::cfg_title)    f="Настройка бэкапа" ;;               en::cfg_title)    f="Backup setup" ;;
    ru::cfg_hint)     f="(Enter — оставить значение по умолчанию)" ;; en::cfg_hint) f="(Enter — keep the default)" ;;
    ru::sec_what)     f="── Что бэкапить ──────────────────────" ;; en::sec_what) f="── What to back up ───────────────────" ;;
    ru::q_dir)        f="Директория для бэкапа" ;;          en::q_dir)        f="Directory to back up" ;;
    ru::dir_absent)   f="Директория '%s' сейчас не существует." ;; en::dir_absent) f="Directory '%s' does not exist yet." ;;
    ru::dir_anyway)   f="Всё равно сохранить этот путь?" ;; en::dir_anyway)  f="Save this path anyway?" ;;
    ru::q_hours)      f="Как часто бэкапить (в часах)" ;;   en::q_hours)      f="How often to back up (in hours)" ;;
    ru::sec_where)    f="── Куда бэкапить ─────────────────────" ;; en::sec_where) f="── Where to back up ──────────────────" ;;
    ru::sec_s3)       f="── Настройки S3 ──────────────────────" ;; en::sec_s3) f="── S3 settings ───────────────────────" ;;
    ru::q_endpoint)   f="S3 Endpoint (напр. https://s3.timeweb.cloud, пусто = AWS)" ;; en::q_endpoint) f="S3 Endpoint (e.g. https://s3.timeweb.cloud, empty = AWS)" ;;
    *::q_region)      f="S3 Region" ;;
    ru::q_bucket)     f="S3 Bucket (имя бакета)" ;;         en::q_bucket)     f="S3 Bucket (bucket name)" ;;
    ru::q_prefix)     f="S3 Prefix (папка внутри бакета)" ;; en::q_prefix)    f="S3 Prefix (folder inside the bucket)" ;;
    *::q_akey)        f="S3 Access Key" ;;
    *::q_skey)        f="S3 Secret Key" ;;
    ru::q_retention)  f="Сколько последних бэкапов хранить в S3 (0 = бесконечно)" ;; en::q_retention) f="How many recent backups to keep in S3 (0 = unlimited)" ;;
    ru::sec_tg)       f="── Настройки Telegram ────────────────" ;; en::sec_tg) f="── Telegram settings ─────────────────" ;;
    ru::tg_howto)     f="Создай бота у %s и узнай chat_id через %s." ;; en::tg_howto) f="Create a bot via %s and get chat_id via %s." ;;
    ru::tg_limit)     f="Лимит Telegram-бота на файл — 50 МБ. Большие архивы не уйдут (используй S3)." ;; en::tg_limit) f="Telegram bot file limit is 50 MB. Large archives won't send (use S3)." ;;
    *::q_token)       f="Telegram Bot Token" ;;
    *::q_chat)        f="Telegram Chat ID" ;;
    ru::review)       f="Проверь настройки:" ;;             en::review)       f="Review your settings:" ;;
    ru::q_save)       f="Сохранить эти настройки?" ;;       en::q_save)       f="Save these settings?" ;;
    ru::cancelled)    f="Отменено, ничего не сохранено." ;; en::cancelled)   f="Cancelled, nothing saved." ;;
    ru::q_cron)       f="Добавить автоматический бэкап в cron (каждые %s ч)?" ;; en::q_cron) f="Add an automatic backup to cron (every %s h)?" ;;
    ru::q_testnow)    f="Сделать тестовый бэкап прямо сейчас?" ;; en::q_testnow) f="Run a test backup right now?" ;;
    ru::done_manage)  f="Готово! Управление:  %s  или  %s" ;; en::done_manage) f="Done! Manage with:  %s  or  %s" ;;
    # --- сводка ---
    ru::empty_paren)  f="(пусто)" ;;                        en::empty_paren)  f="(empty)" ;;
    ru::lbl_dir)      f="Директория " ;;                    en::lbl_dir)      f="Directory  " ;;
    ru::lbl_freq)     f="Частота     " ;;                   en::lbl_freq)     f="Frequency  " ;;
    ru::every_h)      f="каждые %s ч" ;;                    en::every_h)      f="every %s h" ;;
    ru::lbl_target)   f="Куда        " ;;                   en::lbl_target)   f="Target     " ;;
    ru::lbl_keep)     f="Хранить копий" ;;                  en::lbl_keep)     f="Keep copies" ;;
    ru::aws_default)  f="(AWS по умолчанию)" ;;             en::aws_default)  f="(AWS default)" ;;
    # --- бэкап ---
    ru::no_conf_run)  f="Нет конфигурации. Сначала запусти:  %s" ;; en::no_conf_run) f="No configuration. Run first:  %s" ;;
    ru::dir_notfound) f="Директория для бэкапа не найдена: %s" ;; en::dir_notfound) f="Backup directory not found: %s" ;;
    ru::archiving)    f="Архивирую %s → %s" ;;             en::archiving)    f="Archiving %s → %s" ;;
    ru::arch_created) f="Архив создан: %s" ;;              en::arch_created) f="Archive created: %s" ;;
    ru::arch_fail)    f="Ошибка архивации." ;;            en::arch_fail)    f="Archiving failed." ;;
    ru::tg_toobig)    f="Архив %s больше лимита Telegram (50 МБ) — не отправлен." ;; en::tg_toobig) f="Archive %s exceeds the Telegram limit (50 MB) — not sent." ;;
    ru::kept_local_s3) f="Архив остался локально: %s. Для больших бэкапов используй S3." ;; en::kept_local_s3) f="Archive kept locally: %s. Use S3 for large backups." ;;
    *::cap_title)     f="📦 VTSLY backup" ;;
    ru::tg_sending)   f="Отправляю в Telegram (chat %s)..." ;; en::tg_sending) f="Sending to Telegram (chat %s)..." ;;
    ru::tg_sent)      f="Отправлено в Telegram." ;;        en::tg_sent)      f="Sent to Telegram." ;;
    ru::tg_fail_log)  f="Не удалось отправить в Telegram. Проверь токен/chat_id. Лог: %s" ;; en::tg_fail_log) f="Failed to send to Telegram. Check token/chat_id. Log: %s" ;;
    ru::kept_local)   f="Архив остался локально: %s" ;;    en::kept_local)   f="Archive kept locally: %s" ;;
    ru::s3_uploading) f="Загружаю в S3: %s" ;;            en::s3_uploading) f="Uploading to S3: %s" ;;
    ru::s3_uploaded)  f="Загружено в S3." ;;             en::s3_uploaded)  f="Uploaded to S3." ;;
    ru::s3_upfail)    f="Не удалось загрузить в S3. Архив остался локально: %s" ;; en::s3_upfail) f="Failed to upload to S3. Archive kept locally: %s" ;;
    ru::see_log)      f="Смотри лог: %s" ;;               en::see_log)      f="See the log: %s" ;;
    ru::no_target_local) f="Назначение не задано — архив лежит локально: %s" ;; en::no_target_local) f="No target set — archive kept locally: %s" ;;
    ru::backup_done)  f="Бэкап завершён." ;;             en::backup_done)  f="Backup complete." ;;
    ru::clean_old)    f="Чищу старые копии в S3 (удаляю %s)..." ;; en::clean_old) f="Cleaning old copies in S3 (removing %s)..." ;;
    ru::clean_done)   f="Старые копии очищены (храним последние %s)." ;; en::clean_done) f="Old copies cleaned (keeping last %s)." ;;
    # --- проверка соединения ---
    ru::tg_test_send) f="Отправляю тестовое сообщение в Telegram (chat %s)..." ;; en::tg_test_send) f="Sending a test message to Telegram (chat %s)..." ;;
    ru::tg_test_text) f="✅ VTSLY: связь с ботом работает (%s)" ;; en::tg_test_text) f="✅ VTSLY: bot connection works (%s)" ;;
    ru::tg_test_ok)   f="Telegram работает — проверь чат, пришло сообщение." ;; en::tg_test_ok) f="Telegram works — check the chat for the message." ;;
    ru::tg_test_fail) f="Не удалось отправить в Telegram. Проверь токен/chat_id." ;; en::tg_test_fail) f="Failed to send to Telegram. Check token/chat_id." ;;
    ru::s3_checking)  f="Проверяю доступ к бакету %s..." ;; en::s3_checking) f="Checking access to bucket %s..." ;;
    ru::s3_ok)        f="Соединение с S3 работает, бакет доступен." ;; en::s3_ok) f="S3 connection works, bucket is accessible." ;;
    ru::s3_fail)      f="Не удалось получить доступ к S3. Проверь ключи/endpoint/bucket." ;; en::s3_fail) f="Cannot access S3. Check keys/endpoint/bucket." ;;
    # --- cron ---
    ru::cron_set)     f="Cron настроен: %s  (каждые %s ч)" ;; en::cron_set) f="Cron set: %s  (every %s h)" ;;
    ru::cron_removed) f="Задача cron удалена." ;;         en::cron_removed) f="Cron job removed." ;;
    ru::cron_none)    f="Записи VTSLY в cron не найдено." ;; en::cron_none) f="No VTSLY cron entry found." ;;
    ru::cron_active)  f="Активная задача cron:" ;;        en::cron_active)  f="Active cron job:" ;;
    ru::cron_notset)  f="Автобэкап в cron не настроен." ;; en::cron_notset) f="Auto-backup cron is not configured." ;;
    # --- установка / статус ---
    ru::installed_cmd) f="Скрипт установлен как команда: %s" ;; en::installed_cmd) f="Script installed as command: %s" ;;
    ru::cur_conf)     f="Текущая конфигурация:" ;;        en::cur_conf)     f="Current configuration:" ;;
    ru::no_conf_found) f="Конфигурация не найдена. Запусти:  %s" ;; en::no_conf_found) f="No configuration found. Run:  %s" ;;
    ru::lbl_log)      f="Лог: %s" ;;                      en::lbl_log)      f="Log: %s" ;;
    ru::lang_changed) f="Язык интерфейса изменён." ;;     en::lang_changed) f="Interface language changed." ;;
    # --- меню ---
    ru::m_config)     f="Конфиг: %s" ;;                   en::m_config)     f="Config: %s" ;;
    ru::m_noconfig)   f="Конфиг ещё не создан" ;;         en::m_noconfig)   f="Config not created yet" ;;
    ru::m1) f="Настроить бэкап (мастер)" ;;               en::m1) f="Configure backup (wizard)" ;;
    ru::m2) f="Сделать бэкап — сейчас, другая папка, список архивов" ;; en::m2) f="Make a backup — now, another folder, list archives" ;;
    # --- подменю бэкапа ---
    ru::bm_title) f="Меню бэкапа" ;;                       en::bm_title) f="Backup menu" ;;
    ru::bm1) f="Сделать бэкап сейчас (папка из настроек)" ;; en::bm1) f="Run backup now (configured folder)" ;;
    ru::bm2) f="Бэкап другой папки (разово)" ;;            en::bm2) f="Back up another folder (one-time)" ;;
    ru::bm3) f="Показать последние архивы" ;;             en::bm3) f="Show recent archives" ;;
    ru::bm0) f="← Назад" ;;                               en::bm0) f="← Back" ;;
    ru::arch_local_hdr) f="Локальные архивы (%s):" ;;     en::arch_local_hdr) f="Local archives (%s):" ;;
    ru::arch_s3_hdr)    f="Архивы в S3 (%s):" ;;          en::arch_s3_hdr)    f="Archives in S3 (%s):" ;;
    ru::arch_none)      f="пусто" ;;                      en::arch_none)      f="empty" ;;
    ru::arch_tg_note)   f="Архивы хранятся в чате Telegram (бот их не листит)." ;; en::arch_tg_note) f="Archives are stored in the Telegram chat (bot can't list them)." ;;
    ru::onetime_dir)    f="Папка для разового бэкапа" ;;   en::onetime_dir)    f="Folder for the one-time backup" ;;
    ru::m3) f="Проверить соединение (S3/Telegram)" ;;     en::m3) f="Check connection (S3/Telegram)" ;;
    ru::m4) f="Настроить/обновить cron" ;;                en::m4) f="Set up / update cron" ;;
    ru::m5) f="Удалить cron" ;;                           en::m5) f="Remove cron" ;;
    ru::m6) f="Статус и настройки" ;;                     en::m6) f="Status and settings" ;;
    ru::m7) f="Показать лог (последние 30 строк)" ;;      en::m7) f="Show log (last 30 lines)" ;;
    ru::m8) f="Сменить язык / Change language" ;;         en::m8) f="Change language / Сменить язык" ;;
    ru::m0) f="Выход" ;;                                  en::m0) f="Exit" ;;
    ru::log_empty)    f="Лог пуст." ;;                    en::log_empty)    f="Log is empty." ;;
    ru::bye)          f="Пока!" ;;                        en::bye)          f="Bye!" ;;
    ru::no_item)      f="Нет такого пункта." ;;           en::no_item)      f="No such item." ;;
    ru::enter_menu)   f="Enter — в меню..." ;;            en::enter_menu)   f="Enter — back to menu..." ;;
    # --- справка ---
    ru::unknown_cmd)  f="Неизвестная команда: %s" ;;      en::unknown_cmd)  f="Unknown command: %s" ;;
    ru::usage_head)   f="Использование: %s <команда>" ;;  en::usage_head)   f="Usage: %s <command>" ;;
    ru::quickstart)   f="Быстрый старт на сервере:" ;;    en::quickstart)   f="Quick start on the server:" ;;
    ru::u_setup)  f="Мастер настройки (зависимости + конфиг + cron)" ;; en::u_setup) f="Setup wizard (deps + config + cron)" ;;
    ru::u_menu)   f="Интерактивное меню" ;;               en::u_menu)   f="Interactive menu" ;;
    ru::u_backup) f="Сделать бэкап сейчас (tag: manual/auto/...)" ;; en::u_backup) f="Run a backup now (tag: manual/auto/...)" ;;
    ru::u_test)   f="Тестовый ручной бэкап" ;;            en::u_test)   f="Manual test backup" ;;
    ru::u_check)  f="Проверить соединение (S3 или Telegram)" ;; en::u_check) f="Check connection (S3 or Telegram)" ;;
    ru::u_cron)   f="Настроить/обновить задачу cron" ;;   en::u_cron)   f="Set up / update the cron job" ;;
    ru::u_cronrm) f="Удалить задачу cron" ;;              en::u_cronrm) f="Remove the cron job" ;;
    ru::u_status) f="Показать настройки и состояние cron" ;; en::u_status) f="Show settings and cron status" ;;
    ru::u_deps)   f="Только установить зависимости" ;;     en::u_deps)   f="Install dependencies only" ;;
    ru::u_lang)   f="Сменить язык (RU/EN)" ;;             en::u_lang)   f="Change language (RU/EN)" ;;
    ru::u_log)    f="Показать лог" ;;                     en::u_log)    f="Show the log" ;;
    ru::u_help)   f="Эта справка" ;;                     en::u_help)   f="This help" ;;
    *) f="$k" ;;
  esac
  # shellcheck disable=SC2059
  printf -- "$f" "$@"
}

# ====================== БАЗОВЫЕ ХЕЛПЕРЫ ========================
banner() {
  echo -e "${C_CYN}${C_BOLD}"
  cat <<'EOF'
██╗   ██╗████████╗███████╗██╗     ██╗   ██╗
██║   ██║╚══██╔══╝██╔════╝██║     ╚██╗ ██╔╝
██║   ██║   ██║   ███████╗██║      ╚████╔╝
╚██╗ ██╔╝   ██║   ╚════██║██║       ╚██╔╝
 ╚████╔╝    ██║   ███████║███████╗   ██║
  ╚═══╝     ╚═╝   ╚══════╝╚══════╝   ╚═╝
EOF
  echo -e "${C_RESET}${C_DIM}      $(t banner_sub "$VTSLY_VERSION")${C_RESET}\n"
}

log()   { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$VTSLY_LOG" 2>/dev/null; }
info()  { echo -e "${C_BLU}ℹ ${C_RESET}$*"; }
ok()    { echo -e "${C_GRN}✔ ${C_RESET}$*"; }
warn()  { echo -e "${C_YLW}⚠ ${C_RESET}$*"; }
err()   { echo -e "${C_RED}✗ ${C_RESET}$*" >&2; }
die()   { err "$*"; exit 1; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "$(t need_root "$0")"
  fi
}

# --- защита от ошибочного ввода: 1=да / 2=нет (по умолчанию ДА) -
# Принимает цифры (1/2) и буквы (y/n/да/нет) для совместимости.
ask_yes() {
  local prompt="$1" ans
  while true; do
    read -r -p "$(echo -e "${C_YLW}? ${C_RESET}${prompt} ${C_DIM}[$(t yn_hint_yes)]${C_RESET} ")" ans
    ans="$(echo "${ans:-1}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$ans" in
      1|y|yes|да|д) return 0 ;;
      2|n|no|нет|н) return 1 ;;
      *) warn "$(t yn_bad)" ;;
    esac
  done
}

# ask_no — по умолчанию НЕТ
ask_no() {
  local prompt="$1" ans
  while true; do
    read -r -p "$(echo -e "${C_YLW}? ${C_RESET}${prompt} ${C_DIM}[$(t yn_hint_no)]${C_RESET} ")" ans
    ans="$(echo "${ans:-2}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$ans" in
      1|y|yes|да|д) return 0 ;;
      2|n|no|нет|н) return 1 ;;
      *) warn "$(t yn_bad)" ;;
    esac
  done
}

# ask_value "Текст" "значение_по_умолчанию"  -> печатает результат в stdout
ask_value() {
  local prompt="$1" def="${2:-}" val
  if [ -n "$def" ]; then
    read -r -p "$(echo -e "${C_CYN}» ${C_RESET}${prompt} ${C_DIM}[${def}]${C_RESET}: ")" val
    echo "${val:-$def}"
  else
    read -r -p "$(echo -e "${C_CYN}» ${C_RESET}${prompt}: ")" val
    echo "$val"
  fi
}

# ask_required — обязательное поле
ask_required() {
  local prompt="$1" def="${2:-}" val
  while true; do
    val="$(ask_value "$prompt" "$def")"
    [ -n "$val" ] && { echo "$val"; return 0; }
    warn "$(t req_empty)" >&2
  done
}

# ask_secret — ввод секрета без эха
ask_secret() {
  local prompt="$1" def="${2:-}" val
  if [ -n "$def" ]; then
    read -r -s -p "$(echo -e "${C_CYN}» ${C_RESET}${prompt} ${C_DIM}[$(t secret_keep)]${C_RESET}: ")" val
    echo >&2
    echo "${val:-$def}"
  else
    read -r -s -p "$(echo -e "${C_CYN}» ${C_RESET}${prompt}: ")" val
    echo >&2
    echo "$val"
  fi
}

# ask_number — только целое число >= 0
ask_number() {
  local prompt="$1" def="${2:-}" val
  while true; do
    val="$(ask_value "$prompt" "$def")"
    if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; return 0; fi
    warn "$(t need_int)" >&2
  done
}

# ask_target — выбор цели бэкапа: 1) S3  2) Telegram. Печатает s3 / tg
ask_target() {
  local def="${1:-s3}" def_num ans
  [ "$def" = "tg" ] && def_num="2" || def_num="1"
  while true; do
    echo -e "${C_CYN}» ${C_RESET}$(t tgt_where)" >&2
    echo -e "    ${C_BOLD}1${C_RESET}) $(t tgt_s3)" >&2
    echo -e "    ${C_BOLD}2${C_RESET}) $(t tgt_tg)" >&2
    read -r -p "$(echo -e "  ${C_DIM}$(t choice) [${def_num}]${C_RESET}: ")" ans
    ans="$(echo "${ans:-$def_num}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$ans" in
      1|s3)          echo "s3"; return 0 ;;
      2|tg|telegram) echo "tg"; return 0 ;;
      *) warn "$(t tgt_bad)" >&2 ;;
    esac
  done
}

# ask_lang — выбор языка: 1) RU  2) EN. Печатает ru / en
ask_lang() {
  local def="${1:-ru}" def_num ans
  [ "$def" = "en" ] && def_num="2" || def_num="1"
  while true; do
    echo -e "${C_CYN}» ${C_RESET}$(t lang_q)" >&2
    echo -e "    ${C_BOLD}1${C_RESET}) Русский" >&2
    echo -e "    ${C_BOLD}2${C_RESET}) English" >&2
    read -r -p "$(echo -e "  ${C_DIM}[${def_num}]${C_RESET}: ")" ans
    ans="$(echo "${ans:-$def_num}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$ans" in
      1|ru|rus|русский) echo "ru"; return 0 ;;
      2|en|eng|english) echo "en"; return 0 ;;
      *) warn "$(t lang_bad)" >&2 ;;
    esac
  done
}

get_server_ip() {
  local ip
  ip="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null)" \
    || ip="$(hostname -I 2>/dev/null | awk '{print $1}')" \
    || ip="server"
  echo "${ip:-server}"
}

# ====================== УСТАНОВКА ЗАВИСИМОСТЕЙ =================
pkg_install() {
  local pkgs="$*"
  if   command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y $pkgs
  elif command -v dnf    >/dev/null 2>&1; then dnf install -y $pkgs
  elif command -v yum    >/dev/null 2>&1; then yum install -y $pkgs
  elif command -v zypper >/dev/null 2>&1; then zypper -n install $pkgs
  elif command -v apk    >/dev/null 2>&1; then apk add --no-cache $pkgs
  elif command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm $pkgs
  else return 1; fi
}

install_awscli() {
  command -v aws >/dev/null 2>&1 && { ok "$(t aws_have)"; return 0; }
  info "$(t aws_inst)"
  pkg_install awscli >/dev/null 2>&1
  if command -v aws >/dev/null 2>&1; then ok "$(t aws_pkg)"; return 0; fi

  # Запасной путь — официальный установщик AWS CLI v2
  local arch tmp
  arch="$(uname -m)"
  case "$arch" in
    x86_64)        arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) warn "$(t arch_unk "$arch")"; arch="x86_64" ;;
  esac
  tmp="$(mktemp -d)"
  if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$tmp/awscliv2.zip"; then
    ( cd "$tmp" && unzip -q awscliv2.zip && ./aws/install --update ) \
      && ok "$(t aws_v2ok)" || warn "$(t aws_v2fail)"
  fi
  rm -rf "$tmp"
  command -v aws >/dev/null 2>&1
}

ensure_deps() {
  info "$(t deps_check)"
  local need=()
  command -v curl  >/dev/null 2>&1 || need+=(curl)
  command -v tar   >/dev/null 2>&1 || need+=(tar)
  command -v gzip  >/dev/null 2>&1 || need+=(gzip)
  command -v unzip >/dev/null 2>&1 || need+=(unzip)
  if ! command -v crontab >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then need+=(cron); else need+=(cronie); fi
  fi
  if [ "${#need[@]}" -gt 0 ]; then
    info "$(t deps_add "${need[*]}")"
    pkg_install "${need[@]}" || warn "$(t deps_partial)"
  fi
  install_awscli || warn "$(t aws_optional)"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now cron    >/dev/null 2>&1 \
    || systemctl enable --now crond >/dev/null 2>&1 \
    || systemctl enable --now cronie >/dev/null 2>&1 || true
  fi
  ok "$(t deps_ready)"
}

# ========================== КОНФИГ =============================
load_conf() {
  if [ -f "$VTSLY_CONF" ]; then
    # shellcheck disable=SC1090
    source "$VTSLY_CONF"
    VTSLY_LANG="${DEFAULT_LANG:-ru}"
    return 0
  fi
  return 1
}

save_conf() {
  mkdir -p "$VTSLY_HOME"
  cat > "$VTSLY_CONF" <<EOF
# VTSLY configuration — $(date '+%Y-%m-%d %H:%M:%S')
DEFAULT_LANG="${DEFAULT_LANG}"
DEFAULT_BACKUP_TARGET="${DEFAULT_BACKUP_TARGET}"
DEFAULT_S3_ENABLED="${DEFAULT_S3_ENABLED}"
DEFAULT_S3_ENDPOINT="${DEFAULT_S3_ENDPOINT}"
DEFAULT_S3_REGION="${DEFAULT_S3_REGION}"
DEFAULT_S3_BUCKET="${DEFAULT_S3_BUCKET}"
DEFAULT_S3_PREFIX="${DEFAULT_S3_PREFIX}"
DEFAULT_S3_ACCESS_KEY="${DEFAULT_S3_ACCESS_KEY}"
DEFAULT_S3_SECRET_KEY="${DEFAULT_S3_SECRET_KEY}"
DEFAULT_TG_BOT_TOKEN="${DEFAULT_TG_BOT_TOKEN}"
DEFAULT_TG_CHAT_ID="${DEFAULT_TG_CHAT_ID}"
DEFAULT_BACKUP_DIR="${DEFAULT_BACKUP_DIR}"
DEFAULT_BACKUP_EVERY_HOURS="${DEFAULT_BACKUP_EVERY_HOURS}"
DEFAULT_RETENTION="${DEFAULT_RETENTION}"
EOF
  chmod 600 "$VTSLY_CONF"
  ok "$(t cfg_saved "${C_BOLD}${VTSLY_CONF}${C_RESET}")"
}

# ====================== МАСТЕР НАСТРОЙКИ =======================
configure() {
  load_conf || true   # подтянем прошлые значения как дефолты
  DEFAULT_LANG="$(ask_lang "$DEFAULT_LANG")"; VTSLY_LANG="$DEFAULT_LANG"

  banner
  echo -e "${C_BOLD}$(t cfg_title)${C_RESET}  ${C_DIM}$(t cfg_hint)${C_RESET}\n"

  local srv_ip; srv_ip="$(get_server_ip)"
  [ -z "$DEFAULT_S3_PREFIX" ] && DEFAULT_S3_PREFIX="BACKUP/${srv_ip}"

  echo -e "${C_MAG}$(t sec_what)${C_RESET}"
  DEFAULT_BACKUP_DIR="$(ask_required "$(t q_dir)" "$DEFAULT_BACKUP_DIR")"
  if [ ! -d "$DEFAULT_BACKUP_DIR" ]; then
    warn "$(t dir_absent "$DEFAULT_BACKUP_DIR")"
    ask_yes "$(t dir_anyway)" || DEFAULT_BACKUP_DIR="$(ask_required "$(t q_dir)" "/var/www")"
  fi
  DEFAULT_BACKUP_EVERY_HOURS="$(ask_number "$(t q_hours)" "$DEFAULT_BACKUP_EVERY_HOURS")"

  echo -e "\n${C_MAG}$(t sec_where)${C_RESET}"
  DEFAULT_BACKUP_TARGET="$(ask_target "$DEFAULT_BACKUP_TARGET")"

  if [ "$DEFAULT_BACKUP_TARGET" = "s3" ]; then
    DEFAULT_S3_ENABLED="true"
    echo -e "\n${C_MAG}$(t sec_s3)${C_RESET}"
    DEFAULT_S3_ENDPOINT="$(ask_value    "$(t q_endpoint)" "$DEFAULT_S3_ENDPOINT")"
    DEFAULT_S3_REGION="$(ask_value      "$(t q_region)"   "$DEFAULT_S3_REGION")"
    DEFAULT_S3_BUCKET="$(ask_required   "$(t q_bucket)"   "$DEFAULT_S3_BUCKET")"
    DEFAULT_S3_PREFIX="$(ask_value      "$(t q_prefix)"   "$DEFAULT_S3_PREFIX")"
    DEFAULT_S3_ACCESS_KEY="$(ask_required "$(t q_akey)"   "$DEFAULT_S3_ACCESS_KEY")"
    DEFAULT_S3_SECRET_KEY="$(ask_secret   "$(t q_skey)"   "$DEFAULT_S3_SECRET_KEY")"
    DEFAULT_RETENTION="$(ask_number     "$(t q_retention)" "$DEFAULT_RETENTION")"
  else
    DEFAULT_S3_ENABLED="false"
    echo -e "\n${C_MAG}$(t sec_tg)${C_RESET}"
    info "$(t tg_howto "${C_BOLD}@BotFather${C_RESET}" "${C_BOLD}@userinfobot${C_RESET}")"
    warn "$(t tg_limit)"
    DEFAULT_TG_BOT_TOKEN="$(ask_required "$(t q_token)" "$DEFAULT_TG_BOT_TOKEN")"
    DEFAULT_TG_CHAT_ID="$(ask_required   "$(t q_chat)"  "$DEFAULT_TG_CHAT_ID")"
  fi

  echo
  echo -e "${C_BOLD}$(t review)${C_RESET}"
  print_config_summary
  echo
  if ask_yes "$(t q_save)"; then
    save_conf
  else
    warn "$(t cancelled)"; return 1
  fi

  echo
  if ask_yes "$(t q_cron "$DEFAULT_BACKUP_EVERY_HOURS")"; then
    install_cron
  fi

  echo
  if ask_yes "$(t q_testnow)"; then
    run_backup "manual-test"
  fi
  echo
  ok "$(t done_manage "${C_BOLD}vtsly-backup menu${C_RESET}" "${C_BOLD}vtsly-backup --help${C_RESET}")"
}

mask_secret() { local s="$1"; [ -z "$s" ] && { t empty_paren; echo; return; }; echo "****${s: -4}"; }

print_config_summary() {
  local tname; [ "$DEFAULT_BACKUP_TARGET" = "tg" ] && tname="Telegram" || tname="S3"
  echo -e "  ${C_DIM}$(t lbl_dir)  :${C_RESET} ${DEFAULT_BACKUP_DIR}"
  echo -e "  ${C_DIM}$(t lbl_freq) :${C_RESET} $(t every_h "$DEFAULT_BACKUP_EVERY_HOURS")"
  echo -e "  ${C_DIM}$(t lbl_target):${C_RESET} ${C_BOLD}${tname}${C_RESET}"
  if [ "$DEFAULT_BACKUP_TARGET" = "s3" ]; then
    echo -e "  ${C_DIM}$(t lbl_keep) :${C_RESET} ${DEFAULT_RETENTION}"
    echo -e "  ${C_DIM}S3 endpoint :${C_RESET} ${DEFAULT_S3_ENDPOINT:-$(t aws_default)}"
    echo -e "  ${C_DIM}S3 region   :${C_RESET} ${DEFAULT_S3_REGION}"
    echo -e "  ${C_DIM}S3 bucket   :${C_RESET} ${DEFAULT_S3_BUCKET}"
    echo -e "  ${C_DIM}S3 prefix   :${C_RESET} ${DEFAULT_S3_PREFIX}"
    echo -e "  ${C_DIM}Access key  :${C_RESET} $(mask_secret "$DEFAULT_S3_ACCESS_KEY")"
    echo -e "  ${C_DIM}Secret key  :${C_RESET} $(mask_secret "$DEFAULT_S3_SECRET_KEY")"
  else
    echo -e "  ${C_DIM}TG token    :${C_RESET} $(mask_secret "$DEFAULT_TG_BOT_TOKEN")"
    echo -e "  ${C_DIM}TG chat id  :${C_RESET} ${DEFAULT_TG_CHAT_ID}"
  fi
}

# ========================== БЭКАП ==============================
aws_s3() {
  local endpoint_opt=()
  [ -n "$DEFAULT_S3_ENDPOINT" ] && endpoint_opt=(--endpoint-url "$DEFAULT_S3_ENDPOINT")
  AWS_ACCESS_KEY_ID="$DEFAULT_S3_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="$DEFAULT_S3_SECRET_KEY" \
  AWS_DEFAULT_REGION="$DEFAULT_S3_REGION" \
  aws ${endpoint_opt[@]+"${endpoint_opt[@]}"} "$@"
}

# tg_send <файл> <подпись> — документ в Telegram через Bot API
tg_send() {
  local file="$1" caption="$2" resp
  resp="$(curl -fsS --max-time 600 \
        -F "chat_id=${DEFAULT_TG_CHAT_ID}" \
        -F "caption=${caption}" \
        -F "document=@${file}" \
        "https://api.telegram.org/bot${DEFAULT_TG_BOT_TOKEN}/sendDocument" 2>>"$VTSLY_LOG")"
  if echo "$resp" | grep -q '"ok":true'; then return 0; fi
  echo "$resp" >> "$VTSLY_LOG"; return 1
}

# tg_message <текст> — текстовое сообщение (проверка связи)
tg_message() {
  curl -fsS --max-time 30 \
    -F "chat_id=${DEFAULT_TG_CHAT_ID}" \
    -F "text=$1" \
    "https://api.telegram.org/bot${DEFAULT_TG_BOT_TOKEN}/sendMessage" 2>>"$VTSLY_LOG" \
    | grep -q '"ok":true'
}

run_backup() {
  local tag="${1:-auto}" dir_override="${2:-}"
  load_conf || die "$(t no_conf_run "vtsly-backup setup")"
  [ -n "$dir_override" ] && DEFAULT_BACKUP_DIR="$dir_override"
  [ -d "$DEFAULT_BACKUP_DIR" ] || die "$(t dir_notfound "$DEFAULT_BACKUP_DIR")"

  local stamp host base archive
  stamp="$(date '+%Y%m%d-%H%M%S')"
  host="$(hostname -s 2>/dev/null || echo host)"
  base="$(basename "$DEFAULT_BACKUP_DIR")"
  mkdir -p "$VTSLY_BACKUP_DIR_LOCAL"
  archive="${VTSLY_BACKUP_DIR_LOCAL}/${host}_${base}_${stamp}_${tag}.tar.gz"

  info "$(t archiving "${C_BOLD}${DEFAULT_BACKUP_DIR}${C_RESET}" "$(basename "$archive")")"
  log "BACKUP start dir=$DEFAULT_BACKUP_DIR tag=$tag"

  if tar -czf "$archive" -C "$(dirname "$DEFAULT_BACKUP_DIR")" "$base" 2>>"$VTSLY_LOG"; then
    ok "$(t arch_created "$(du -h "$archive" | cut -f1)")"
  else
    err "$(t arch_fail)"; log "BACKUP tar FAILED"; return 1
  fi

  if [ "$DEFAULT_BACKUP_TARGET" = "tg" ]; then
    # ---- Telegram ----
    local size_b; size_b="$(stat -c%s "$archive" 2>/dev/null || echo 0)"
    if [ "$size_b" -gt "$TG_LIMIT_BYTES" ]; then
      err "$(t tg_toobig "$(du -h "$archive" | cut -f1)")"
      err "$(t kept_local_s3 "$archive")"
      log "BACKUP tg SKIPPED too big ($size_b)"
      return 1
    fi
    local cap; cap="$(t cap_title)
host: $(hostname -f 2>/dev/null || hostname)
dir:  ${DEFAULT_BACKUP_DIR}
file: $(basename "$archive")
date: $(date '+%Y-%m-%d %H:%M:%S')"
    info "$(t tg_sending "$DEFAULT_TG_CHAT_ID")"
    if tg_send "$archive" "$cap"; then
      ok "$(t tg_sent)"
      log "BACKUP sent to telegram $(basename "$archive")"
      [ "$tag" = "auto" ] && rm -f "$archive"
    else
      err "$(t tg_fail_log "$VTSLY_LOG")"
      err "$(t kept_local "$archive")"
      log "BACKUP telegram FAILED"; return 1
    fi
  elif [ "$DEFAULT_S3_ENABLED" = "true" ]; then
    # ---- S3 ----
    local dest="s3://${DEFAULT_S3_BUCKET}/${DEFAULT_S3_PREFIX%/}/$(basename "$archive")"
    info "$(t s3_uploading "${C_BOLD}${dest}${C_RESET}")"
    if aws_s3 s3 cp "$archive" "$dest" >>"$VTSLY_LOG" 2>&1; then
      ok "$(t s3_uploaded)"
      log "BACKUP uploaded $dest"
      [ "$tag" = "auto" ] && rm -f "$archive"
      cleanup_old
    else
      err "$(t s3_upfail "$archive")"
      err "$(t see_log "$VTSLY_LOG")"
      log "BACKUP upload FAILED"; return 1
    fi
  else
    ok "$(t no_target_local "${C_BOLD}${archive}${C_RESET}")"
  fi
  ok "$(t backup_done)"
}

cleanup_old() {
  [ "${DEFAULT_RETENTION:-0}" -gt 0 ] 2>/dev/null || return 0
  [ "$DEFAULT_S3_ENABLED" = "true" ] || return 0
  local prefix="s3://${DEFAULT_S3_BUCKET}/${DEFAULT_S3_PREFIX%/}/"
  local keys total to_del
  keys="$(aws_s3 s3 ls "$prefix" 2>/dev/null | awk '{print $4}' | grep -E '\.tar\.gz$' | sort)"
  total="$(echo "$keys" | grep -c .)"
  to_del=$(( total - DEFAULT_RETENTION ))
  [ "$to_del" -gt 0 ] || return 0
  info "$(t clean_old "$to_del")"
  echo "$keys" | head -n "$to_del" | while read -r k; do
    [ -n "$k" ] && aws_s3 s3 rm "${prefix}${k}" >>"$VTSLY_LOG" 2>&1 && echo -e "  ${C_DIM}- $k${C_RESET}"
  done
  ok "$(t clean_done "$DEFAULT_RETENTION")"
}

test_connection() {
  load_conf || die "$(t no_conf_run "vtsly-backup setup")"
  if [ "$DEFAULT_BACKUP_TARGET" = "tg" ]; then
    info "$(t tg_test_send "$DEFAULT_TG_CHAT_ID")"
    if tg_message "$(t tg_test_text "$(hostname 2>/dev/null)")"; then
      ok "$(t tg_test_ok)"
    else
      err "$(t tg_test_fail)"; return 1
    fi
  else
    info "$(t s3_checking "${C_BOLD}${DEFAULT_S3_BUCKET}${C_RESET}")"
    if aws_s3 s3 ls "s3://${DEFAULT_S3_BUCKET}/${DEFAULT_S3_PREFIX%/}/" >/dev/null 2>&1; then
      ok "$(t s3_ok)"
    else
      err "$(t s3_fail)"; return 1
    fi
  fi
}

# ============================ CRON ============================
install_cron() {
  load_conf || die "$(t no_conf_run "vtsly-backup setup")"
  local hours="${DEFAULT_BACKUP_EVERY_HOURS:-24}" schedule
  if [ "$hours" -ge 24 ] && [ $(( hours % 24 )) -eq 0 ]; then
    local days=$(( hours / 24 ))
    if [ "$days" -le 1 ]; then schedule="0 3 * * *"
    else schedule="0 3 */${days} * *"; fi
  else
    schedule="0 */${hours} * * *"
  fi
  local line="${schedule} ${VTSLY_BIN} backup auto >/dev/null 2>&1 ${CRON_TAG}"
  ( crontab -l 2>/dev/null | grep -v "$CRON_TAG"; echo "$line" ) | crontab -
  ok "$(t cron_set "${C_BOLD}${schedule}${C_RESET}" "$hours")"
  log "CRON installed: $line"
}

remove_cron() {
  if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
    crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab -
    ok "$(t cron_removed)"
  else
    warn "$(t cron_none)"
  fi
}

show_cron() {
  local c; c="$(crontab -l 2>/dev/null | grep "$CRON_TAG")"
  if [ -n "$c" ]; then echo -e "${C_GRN}$(t cron_active)${C_RESET}\n  $c"
  else warn "$(t cron_notset)"; fi
}

set_lang() {
  load_conf || die "$(t no_conf_run "vtsly-backup setup")"
  DEFAULT_LANG="$(ask_lang "$DEFAULT_LANG")"; VTSLY_LANG="$DEFAULT_LANG"
  save_conf
  ok "$(t lang_changed)"
}

# ====================== УСТАНОВКА КОМАНДЫ =====================
self_install() {
  need_root
  if [ "$VTSLY_SELF" != "$VTSLY_BIN" ]; then
    cp -f "$VTSLY_SELF" "$VTSLY_BIN"
    chmod +x "$VTSLY_BIN"
    ok "$(t installed_cmd "${C_BOLD}vtsly-backup${C_RESET}")"
  fi
}

status() {
  banner
  if load_conf; then
    echo -e "${C_BOLD}$(t cur_conf)${C_RESET}"
    print_config_summary
  else
    warn "$(t no_conf_found "${C_BOLD}vtsly-backup setup${C_RESET}")"
  fi
  echo
  show_cron
  echo
  echo -e "${C_DIM}$(t lbl_log "$VTSLY_LOG")${C_RESET}"
}

# ====================== СПИСОК АРХИВОВ ========================
list_archives() {
  load_conf || die "$(t no_conf_run "vtsly-backup setup")"
  local f found=0
  echo -e "${C_BOLD}$(t arch_local_hdr "$VTSLY_BACKUP_DIR_LOCAL")${C_RESET}"
  for f in "$VTSLY_BACKUP_DIR_LOCAL"/*.tar.gz; do
    [ -e "$f" ] || break
    echo -e "  ${C_DIM}$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)${C_RESET}  $(basename "$f")  ($(du -h "$f" | cut -f1))"
    found=1
  done
  [ "$found" -eq 0 ] && echo -e "  ${C_DIM}$(t arch_none)${C_RESET}"

  if [ "$DEFAULT_BACKUP_TARGET" = "s3" ]; then
    local prefix="s3://${DEFAULT_S3_BUCKET}/${DEFAULT_S3_PREFIX%/}/"
    echo
    echo -e "${C_BOLD}$(t arch_s3_hdr "$prefix")${C_RESET}"
    local out
    out="$(aws_s3 s3 ls "$prefix" 2>/dev/null | awk '$4 ~ /\.tar\.gz$/ {print "  "$1" "$2"  "$4"  ("$3" B)"}')"
    if [ -n "$out" ]; then echo "$out"; else echo -e "  ${C_DIM}$(t arch_none)${C_RESET}"; fi
  elif [ "$DEFAULT_BACKUP_TARGET" = "tg" ]; then
    echo
    info "$(t arch_tg_note)"
  fi
}

# ====================== ПОДМЕНЮ БЭКАПА ========================
menu_backup() {
  while true; do
    banner
    echo -e "${C_BOLD}$(t bm_title)${C_RESET}\n"
    echo -e "  ${C_BOLD}1${C_RESET}) $(t bm1)"
    echo -e "  ${C_BOLD}2${C_RESET}) $(t bm2)"
    echo -e "  ${C_BOLD}3${C_RESET}) $(t bm3)"
    echo -e "  ${C_BOLD}0${C_RESET}) $(t bm0)"
    echo
    local ch; ch="$(ask_value "$(t choice)" "")"
    echo
    case "$ch" in
      1) run_backup "manual" ;;
      2) local d; d="$(ask_required "$(t onetime_dir)" "")"; run_backup "manual" "$d" ;;
      3) list_archives ;;
      0|q|back|назад) return 0 ;;
      *) warn "$(t no_item)" ;;
    esac
    echo
    read -r -p "$(echo -e "${C_DIM}$(t enter_menu)${C_RESET}")" _
  done
}

# ============================ МЕНЮ ============================
menu() {
  while true; do
    banner
    if load_conf 2>/dev/null; then
      echo -e "${C_DIM}$(t m_config "$VTSLY_CONF")${C_RESET}\n"
    else
      echo -e "${C_YLW}$(t m_noconfig)${C_RESET}\n"
    fi
    echo -e "  ${C_BOLD}1${C_RESET}) $(t m1)"
    echo -e "  ${C_BOLD}2${C_RESET}) $(t m2)"
    echo -e "  ${C_BOLD}3${C_RESET}) $(t m3)"
    echo -e "  ${C_BOLD}4${C_RESET}) $(t m4)"
    echo -e "  ${C_BOLD}5${C_RESET}) $(t m5)"
    echo -e "  ${C_BOLD}6${C_RESET}) $(t m6)"
    echo -e "  ${C_BOLD}7${C_RESET}) $(t m7)"
    echo -e "  ${C_BOLD}8${C_RESET}) $(t m8)"
    echo -e "  ${C_BOLD}0${C_RESET}) $(t m0)"
    echo
    local ch; ch="$(ask_value "$(t choice)" "")"
    echo
    case "$ch" in
      1) configure ;;
      2) menu_backup ;;
      3) test_connection ;;
      4) install_cron ;;
      5) remove_cron ;;
      6) status ;;
      7) tail -n 30 "$VTSLY_LOG" 2>/dev/null || warn "$(t log_empty)" ;;
      8) set_lang ;;
      0|q|exit) ok "$(t bye)"; exit 0 ;;
      *) warn "$(t no_item)" ;;
    esac
    echo
    read -r -p "$(echo -e "${C_DIM}$(t enter_menu)${C_RESET}")" _
  done
}

usage() {
  banner
  echo -e "$(t usage_head "${C_BOLD}vtsly-backup${C_RESET}")\n"
  echo -e "  ${C_GRN}setup${C_RESET}          $(t u_setup)"
  echo -e "  ${C_GRN}menu${C_RESET}           $(t u_menu)"
  echo -e "  ${C_GRN}backup [tag]${C_RESET}   $(t u_backup)"
  echo -e "  ${C_GRN}test${C_RESET}           $(t u_test)"
  echo -e "  ${C_GRN}check${C_RESET}          $(t u_check)"
  echo -e "  ${C_GRN}cron${C_RESET}           $(t u_cron)"
  echo -e "  ${C_GRN}cron-remove${C_RESET}    $(t u_cronrm)"
  echo -e "  ${C_GRN}status${C_RESET}         $(t u_status)"
  echo -e "  ${C_GRN}install-deps${C_RESET}   $(t u_deps)"
  echo -e "  ${C_GRN}lang${C_RESET}           $(t u_lang)"
  echo -e "  ${C_GRN}log${C_RESET}            $(t u_log)"
  echo -e "  ${C_GRN}--help${C_RESET}         $(t u_help)"
  echo
  echo -e "${C_BOLD}$(t quickstart)${C_RESET}"
  echo -e "  ${C_DIM}sudo bash vtsly-backup.sh setup${C_RESET}"
}

# ====================== РАННЕЕ ОПРЕДЕЛЕНИЕ ЯЗЫКА ===============
# Подхватываем язык из конфига для команд, которые не вызывают load_conf
# до первого вывода (например, справки), не требуя при этом root.
detect_lang_early() {
  if [ -r "$VTSLY_CONF" ]; then
    local l
    l="$(grep -E '^DEFAULT_LANG=' "$VTSLY_CONF" 2>/dev/null | head -1 | cut -d'"' -f2)"
    [ -n "$l" ] && VTSLY_LANG="$l"
  fi
}

# ============================ MAIN ===========================
main() {
  detect_lang_early
  local cmd="${1:-menu}"; shift || true
  case "$cmd" in
    setup|install)        need_root; ensure_deps; self_install; configure ;;
    install-deps|deps)    need_root; ensure_deps ;;
    configure|config)     need_root; configure ;;
    menu|"")              need_root; menu ;;
    backup)               run_backup "${1:-auto}" ;;
    test)                 run_backup "manual-test" ;;
    check)                test_connection ;;
    cron)                 need_root; install_cron ;;
    cron-remove|uncron)   need_root; remove_cron ;;
    lang|language)        need_root; set_lang ;;
    status)               status ;;
    log)                  tail -n 50 "$VTSLY_LOG" 2>/dev/null || warn "$(t log_empty)" ;;
    -h|--help|help)       usage ;;
    *)                    err "$(t unknown_cmd "$cmd")"; echo; usage; exit 1 ;;
  esac
}

main "$@"
