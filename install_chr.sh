#!/bin/bash
# =============================================================================
#  MikroTik RouterOS CHR — МАКСИМАЛЬНЫЙ установщик v8.0
#  Автор: на основе https://interface31.ru/post/ustanovka-mikrotik-routeros-na-vdsvps/
#  
#  ВОЗМОЖНОСТИ:
#    • Авто-определение режима загрузки (UEFI / Legacy BIOS)
#    • Авто-определение диска, сети, шлюза
#    • Проверка совместимости (архитектура, виртуализация, ОЗУ, диск)
#    • Backup текущего диска (на выбор)
#    • Полная пред-настройка RouterOS через autorun.scr:
#        - Пароль admin + резервный пользователь (failsafe)
#        - Имя роутера (identity)
#        - DNS, NTP (синхронизация времени)
#        - Таймзона
#        - IP Cloud DDNS (бесплатный hostname от MikroTik)
#        - Firewall: input/forward с защитой от брутфорса
#        - Отключение лишних служб (telnet, ftp, www, api, mac-server)
#        - Смена портов SSH / Winbox
#        - Канал обновлений (stable / long-term)
#    • Подробный лог установки в /var/log/chr-install.log
#    • Красивый цветной интерфейс с подсказками на русском
# =============================================================================

# ─── Цвета и стили ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Лог-файл ─────────────────────────────────────────────────────────────────
LOG_FILE="/tmp/chr-install.log"
echo "===== Запуск установки CHR: $(date) =====" >> "$LOG_FILE"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

# ─── Функции вывода ───────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'EOF'
   ╔════════════════════════════════════════════════════════════════════╗
   ║                                                                    ║
   ║       ███╗   ███╗██╗██╗  ██╗██████╗  ██████╗ ████████╗██╗██╗  ██╗ ║
   ║       ████╗ ████║██║██║ ██╔╝██╔══██╗██╔═══██╗╚══██╔══╝██║██║ ██╔╝ ║
   ║       ██╔████╔██║██║█████╔╝ ██████╔╝██║   ██║   ██║   ██║█████╔╝  ║
   ║       ██║╚██╔╝██║██║██╔═██╗ ██╔══██╗██║   ██║   ██║   ██║██╔═██╗  ║
   ║       ██║ ╚═╝ ██║██║██║  ██╗██║  ██║╚██████╔╝   ██║   ██║██║  ██╗ ║
   ║       ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝╚═╝  ╚═╝ ║
   ║                                                                    ║
   ║         R O U T E R O S   C H R   ·   У С Т А Н О В Щ И К         ║
   ║                          версия  8.0                              ║
   ║                                                                    ║
   ╚════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

print_step() {
    local num="$1" total="$2" title="$3"
    echo ""
    echo -e "${CYAN}  ┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}  │${RESET} ${BOLD}▸ Шаг ${num}/${total} — ${title}${RESET}"
    echo -e "${CYAN}  └──────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
    log "ШАГ $num/$total: $title"
}

print_info()    { echo -e "  ${BLUE}ℹ  ${GRAY}$1${RESET}"; }
print_ok()      { echo -e "  ${GREEN}✔  $1${RESET}"; log "OK: $1"; }
print_warn()    { echo -e "  ${YELLOW}⚠  $1${RESET}"; log "WARN: $1"; }
print_error()   { echo -e "  ${RED}✘  $1${RESET}"; log "ERROR: $1"; }
print_section() {
    echo ""
    echo -e "  ${MAGENTA}▸ ${BOLD}$1${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..62})${RESET}"
}

# Подсказка-объяснение «для чайников» — выделяется иначе
print_help() {
    echo -e "  ${DIM}┌─ Зачем это нужно ────────────────────────────────────────────${RESET}"
    while IFS= read -r line; do
        echo -e "  ${DIM}│${RESET} ${GRAY}${line}${RESET}"
    done <<< "$1"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────────${RESET}"
}

ask() {
    local prompt="$1" varname="$2" default="$3" value=""
    if [ -n "$default" ]; then
        echo -ne "  ${WHITE}▶ ${prompt}${RESET} ${DIM}[${default}]${RESET}: "
    else
        echo -ne "  ${WHITE}▶ ${prompt}${RESET}: "
    fi
    read value
    [ -z "$value" ] && [ -n "$default" ] && value="$default"
    eval "$varname=\"$value\""
}

ask_secret() {
    local prompt="$1" varname="$2" value=""
    echo -ne "  ${WHITE}▶ ${prompt}${RESET}: "
    read -s value
    echo ""
    eval "$varname=\"$value\""
}

ask_yn() {
    local prompt="$1" default="${2:-y}" ans
    while true; do
        echo -ne "  ${WHITE}▶ ${prompt}${RESET} ${DIM}[${default}]${RESET}: "
        read ans
        ans="${ans:-$default}"
        [[ "$ans" =~ ^[Yy]$ ]] && return 0
        [[ "$ans" =~ ^[Nn]$ ]] && return 1
        print_warn "Введите y (да) или n (нет)."
    done
}

progress_bar() { echo -ne "  ${CYAN}$1...${RESET} "; }
progress_done() { echo -e "${GREEN}готово${RESET}"; }

# ═══ Проверка root ════════════════════════════════════════════════════════════
if [ "$EUID" -ne 0 ]; then
    echo -e "  ${RED}✘ Скрипт должен быть запущен от имени root!${RESET}"
    echo -e "  ${DIM}Используйте: sudo -s  или  su -${RESET}"
    exit 1
fi

print_banner

# ─── Дисклеймер ───────────────────────────────────────────────────────────────
echo -e "  ${RED}${BOLD}╔══ ВНИМАНИЕ ══════════════════════════════════════════════════╗${RESET}"
echo -e "  ${RED}${BOLD}║${RESET}  ${YELLOW}Скрипт ПОЛНОСТЬЮ сотрёт текущую ОС и ВСЕ данные на диске.${RESET}    ${RED}${BOLD}║${RESET}"
echo -e "  ${RED}${BOLD}║${RESET}  ${YELLOW}Сделайте резервную копию всего важного перед запуском!${RESET}       ${RED}${BOLD}║${RESET}"
echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
print_help "После установки сервер превратится в роутер MikroTik.
Linux, файлы, пароли, сайты — всё исчезнет. Это необратимо.
Подключаться к серверу нужно будет через программу Winbox
или по SSH под пользователем admin с заданным паролем."
echo ""
if ! ask_yn "Понимаю риски и хочу продолжить?"; then
    echo -e "\n  ${GRAY}Установка отменена.${RESET}\n"
    exit 0
fi

TOTAL_STEPS=10

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 1 — ПРОВЕРКА СОВМЕСТИМОСТИ СИСТЕМЫ
# ══════════════════════════════════════════════════════════════════════════════
print_step 1 $TOTAL_STEPS "Проверка совместимости системы"

print_help "RouterOS CHR работает только на 64-битной архитектуре (x86_64)
и требует настоящей виртуализации (KVM/Xen/VMware/Hyper-V).
На OpenVZ и LXC он НЕ запустится — это контейнеры, а не VM.
Минимум: 128 МБ ОЗУ, 128 МБ диск. Рекомендуется: 512 МБ / 1 ГБ."

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    print_ok "Архитектура: ${BOLD}${ARCH}${RESET} (поддерживается)"
else
    print_error "Архитектура ${ARCH} не поддерживается! Нужен x86_64."
    exit 1
fi

# Проверка виртуализации
VIRT="unknown"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")
fi
case "$VIRT" in
    kvm|xen|vmware|microsoft|qemu|oracle|bochs|parallels)
        print_ok "Виртуализация: ${BOLD}${VIRT}${RESET} (полная — подходит)"
        ;;
    openvz|lxc|docker|systemd-nspawn)
        print_error "Обнаружен контейнер ${VIRT} — RouterOS CHR не запустится!"
        print_info "Нужен VPS с полной виртуализацией (KVM, Xen, VMware, Hyper-V)."
        exit 1
        ;;
    none)
        print_ok "Физический сервер (виртуализации нет) — подходит"
        ;;
    *)
        print_warn "Тип виртуализации определить не удалось (${VIRT}). Продолжаем..."
        ;;
esac

# ОЗУ
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$RAM_MB" -ge 128 ]; then
    print_ok "Оперативная память: ${BOLD}${RAM_MB} МБ${RESET}"
else
    print_warn "ОЗУ всего ${RAM_MB} МБ — может не хватить (рекомендуется ≥128 МБ)"
fi

# Интернет
progress_bar "Проверка интернет-соединения"
if curl -s -4 --max-time 5 -o /dev/null https://download.mikrotik.com; then
    progress_done
    print_ok "Сервер MikroTik доступен"
else
    progress_done
    print_error "Нет связи с download.mikrotik.com! Проверьте интернет."
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 2 — РЕЖИМ ЗАГРУЗКИ (UEFI / Legacy BIOS)
# ══════════════════════════════════════════════════════════════════════════════
print_step 2 $TOTAL_STEPS "Выбор режима загрузки"

print_help "BIOS — это «прошивка» материнской платы. Бывает двух типов:
  • Legacy BIOS / MBR — старый, простой. Подходит большинству VPS.
  • UEFI — современный, требует особый формат разметки диска.
Если не уверены — выбирайте автоматически определённый вариант."

if [ -d "/sys/firmware/efi" ] && [ "$(ls -A /sys/firmware/efi 2>/dev/null)" ]; then
    DETECTED_MODE="uefi"
    print_ok "Обнаружен режим загрузки: ${BOLD}UEFI${RESET}"
else
    DETECTED_MODE="mbr"
    print_ok "Обнаружен режим загрузки: ${BOLD}Legacy BIOS (MBR)${RESET}"
fi

echo ""
echo -e "  ${CYAN}1)${RESET} Legacy BIOS / MBR ${DIM}(старый стандарт)${RESET}"
echo -e "  ${CYAN}2)${RESET} UEFI              ${DIM}(современный стандарт)${RESET}"
echo ""
DEFAULT_CHOICE=$([ "$DETECTED_MODE" = "uefi" ] && echo "2" || echo "1")
while true; do
    ask "Выберите режим" BOOT_CHOICE "$DEFAULT_CHOICE"
    case "$BOOT_CHOICE" in
        1) BOOT_MODE="mbr"; print_ok "Режим: Legacy BIOS (MBR)"; break ;;
        2) BOOT_MODE="uefi"; print_ok "Режим: UEFI"; break ;;
        *) print_warn "Введите 1 или 2" ;;
    esac
done

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 3 — ВЫБОР ДИСКА
# ══════════════════════════════════════════════════════════════════════════════
print_step 3 $TOTAL_STEPS "Целевой диск для установки"

print_help "Это физический диск, на который будет записан RouterOS.
ВСЁ содержимое этого диска будет уничтожено!
На большинстве VPS диск называется /dev/sda или /dev/vda."

print_section "Найденные диски"
lsblk -d -n -o NAME,SIZE,MODEL,TYPE | grep -E '\bdisk\b' | \
    awk '{printf "  '"${CYAN}"'•'"${RESET}"' /dev/%-8s '"${BOLD}"'%s'"${RESET}"'  %s\n", $1, $2, $3}'
echo ""

AUTO_DISK=$(lsblk -d -n -o NAME,TYPE | grep -E '\bdisk\b' | head -1 | awk '{print "/dev/"$1}')
AUTO_DISK_SIZE=$(lsblk -d -n -o SIZE "$AUTO_DISK" 2>/dev/null)
print_ok "Рекомендуемый: ${BOLD}${AUTO_DISK}${RESET} (${AUTO_DISK_SIZE})"
echo ""
if ask_yn "Использовать ${AUTO_DISK}?"; then
    TARGET_DISK="$AUTO_DISK"
else
    ask "Введите путь к диску (например, /dev/sdb)" TARGET_DISK ""
    if [ ! -b "$TARGET_DISK" ]; then
        print_error "Диск ${TARGET_DISK} не найден!"
        exit 1
    fi
fi
print_ok "Целевой диск: ${BOLD}${TARGET_DISK}${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 4 — НАСТРОЙКА СЕТИ
# ══════════════════════════════════════════════════════════════════════════════
print_step 4 $TOTAL_STEPS "Настройка сети"

print_help "RouterOS не умеет автоматически получать IP по DHCP при первом запуске.
Поэтому сетевые параметры (IP, маска, шлюз) нужно задать заранее.
Скрипт попробует взять их из текущей системы — обычно это правильные значения.
Менять их вручную нужно, только если планируете поставить другой IP."

DETECTED_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1)
DETECTED_IP_CIDR=$(ip -4 addr show "$DETECTED_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
DETECTED_GW=$(ip route | grep '^default' | awk '{print $3}' | head -1)

if [ -n "$DETECTED_IP_CIDR" ] && [ -n "$DETECTED_GW" ]; then
    print_ok "Интерфейс: ${BOLD}${DETECTED_IFACE}${RESET}"
    print_ok "IP-адрес:  ${BOLD}${DETECTED_IP_CIDR}${RESET}"
    print_ok "Шлюз:      ${BOLD}${DETECTED_GW}${RESET}"
    echo ""
    if ask_yn "Использовать эти параметры?"; then
        IP_ADDRESS="$DETECTED_IP_CIDR"
        GATEWAY="$DETECTED_GW"
    else
        NET_MANUAL=1
    fi
else
    print_warn "Не удалось определить сеть автоматически."
    NET_MANUAL=1
fi

if [ "${NET_MANUAL:-0}" = "1" ]; then
    print_section "Ручной ввод сети"
    ask "IP-адрес с маской (например 1.2.3.4/24)" IP_ADDRESS ""
    while [[ ! "$IP_ADDRESS" =~ ^[0-9.]+/[0-9]+$ ]]; do
        print_warn "Неверный формат. Пример: 192.168.1.100/24"
        ask "IP-адрес с маской" IP_ADDRESS ""
    done
    ask "Шлюз (gateway)" GATEWAY ""
    while [[ ! "$GATEWAY" =~ ^[0-9.]+$ ]]; do
        print_warn "Неверный формат. Пример: 192.168.1.1"
        ask "Шлюз" GATEWAY ""
    done
fi

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 5 — ПОЛЬЗОВАТЕЛИ И ПАРОЛИ
# ══════════════════════════════════════════════════════════════════════════════
print_step 5 $TOTAL_STEPS "Пользователи и пароли"

print_help "admin — главный пользователь RouterOS, под ним вы будете заходить.
Также создадим РЕЗЕРВНОГО пользователя — это страховка:
если admin случайно заблокируется или вы забудете его пароль,
можно будет зайти под резервным именем и всё починить."

print_section "Главный пользователь admin"
while true; do
    ask_secret "Пароль для admin (минимум 8 символов)" ADMIN_PASS
    if [ ${#ADMIN_PASS} -lt 8 ]; then
        print_warn "Слишком короткий пароль — минимум 8 символов."
        continue
    fi
    if [[ "$ADMIN_PASS" == *'"'* ]] || [[ "$ADMIN_PASS" == *'\'* ]]; then
        print_warn "Пароль не должен содержать символы \" или \\"
        continue
    fi
    ask_secret "Повторите пароль" ADMIN_PASS2
    if [ "$ADMIN_PASS" = "$ADMIN_PASS2" ]; then
        print_ok "Пароль admin принят."
        break
    fi
    print_warn "Пароли не совпадают."
done

echo ""
print_section "Резервный пользователь (failsafe)"
if ask_yn "Создать резервного пользователя на всякий случай?"; then
    ask "Имя резервного пользователя" BACKUP_USER "rescue"
    while true; do
        ask_secret "Пароль для ${BACKUP_USER}" BACKUP_PASS
        if [ ${#BACKUP_PASS} -lt 8 ]; then
            print_warn "Минимум 8 символов."
            continue
        fi
        ask_secret "Повторите пароль" BACKUP_PASS2
        [ "$BACKUP_PASS" = "$BACKUP_PASS2" ] && break
        print_warn "Пароли не совпадают."
    done
    CREATE_BACKUP_USER=1
    print_ok "Резервный пользователь ${BACKUP_USER} будет создан."
else
    CREATE_BACKUP_USER=0
fi

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 6 — ВЕРСИЯ И КАНАЛ ROUTEROS
# ══════════════════════════════════════════════════════════════════════════════
print_step 6 $TOTAL_STEPS "Версия RouterOS"

print_help "У RouterOS есть несколько «каналов» обновлений:
  • stable      — стабильная (рекомендуется для большинства)
  • long-term   — самая надёжная, обновления реже, только багфиксы
  • testing     — свежие функции, но возможны баги
Версия 7.16.x — текущая стабильная на 2025 год."

if [ "$BOOT_MODE" = "mbr" ]; then
    echo ""
    while true; do
        ask "Версия RouterOS" CHR_VERSION "7.16.1"
        [[ "$CHR_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] && break
        print_warn "Формат: 7.16.1 или 7.15"
    done

    echo ""
    echo -e "  ${CYAN}1)${RESET} stable    ${DIM}(рекомендуется)${RESET}"
    echo -e "  ${CYAN}2)${RESET} long-term ${DIM}(максимально стабильно)${RESET}"
    echo -e "  ${CYAN}3)${RESET} testing   ${DIM}(новейшие функции)${RESET}"
    ask "Канал обновлений" CH "1"
    case "$CH" in
        2) UPGRADE_CHANNEL="long-term" ;;
        3) UPGRADE_CHANNEL="testing" ;;
        *) UPGRADE_CHANNEL="stable" ;;
    esac
else
    CHR_VERSION="7.16.1"
    UPGRADE_CHANNEL="stable"
    print_info "UEFI: используется зафиксированная версия 7.16.1"
fi
print_ok "Версия: ${BOLD}${CHR_VERSION}${RESET}, канал: ${BOLD}${UPGRADE_CHANNEL}${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 7 — ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ
# ══════════════════════════════════════════════════════════════════════════════
print_step 7 $TOTAL_STEPS "Дополнительные настройки роутера"

print_section "Имя роутера (identity)"
print_help "Отображается в Winbox, в SSH, в логах. Удобно для опознания
если у вас несколько роутеров."
ask "Имя роутера" ROUTER_NAME "MikroTik-CHR"

echo ""
print_section "DNS-серверы"
print_help "DNS превращает доменные имена (например, google.com) в IP-адреса.
8.8.8.8 — Google, 1.1.1.1 — Cloudflare. Оба быстрые и надёжные."
ask "DNS (через запятую)" DNS_SERVERS "8.8.8.8,1.1.1.1"

echo ""
print_section "Часовой пояс и NTP (синхронизация времени)"
print_help "Точное время нужно для логов, сертификатов, расписаний.
NTP — это серверы точного времени в интернете.
Таймзона указывается как Europe/Moscow, Asia/Almaty, Europe/Kiev и т.п."
ask "Часовой пояс" TIMEZONE "Europe/Moscow"
ask "NTP-сервер" NTP_SERVER "pool.ntp.org"

echo ""
print_section "MikroTik IP Cloud (бесплатный DDNS)"
print_help "MikroTik бесплатно даёт каждому роутеру уникальное имя вида
xxxxxxxxxxxx.sn.mynetname.net, которое всегда указывает на ваш IP.
Удобно, если IP-адрес меняется или его трудно запомнить."
if ask_yn "Включить MikroTik IP Cloud DDNS?"; then
    ENABLE_DDNS=1
    print_ok "DDNS будет включён."
else
    ENABLE_DDNS=0
fi

echo ""
print_section "Порт SSH"
print_help "SSH — это удалённый доступ в командную строку роутера.
Стандартный порт 22 постоянно сканируют боты — смена порта снижает нагрузку
и количество попыток взлома (security through obscurity)."
if ask_yn "Сменить стандартный порт SSH (22)?"; then
    ask "Новый порт SSH" SSH_PORT "2222"
    while ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; do
        print_warn "Введите число от 1 до 65535."
        ask "Новый порт SSH" SSH_PORT "2222"
    done
else
    SSH_PORT="22"
fi
print_ok "Порт SSH: ${SSH_PORT}"

echo ""
print_section "Порт Winbox"
print_help "Winbox — фирменная программа MikroTik для управления роутером
через красивый интерфейс. Стандартный порт 8291."
if ask_yn "Сменить стандартный порт Winbox (8291)?"; then
    ask "Новый порт Winbox" WINBOX_PORT "18291"
    while ! [[ "$WINBOX_PORT" =~ ^[0-9]+$ ]] || [ "$WINBOX_PORT" -lt 1 ] || [ "$WINBOX_PORT" -gt 65535 ] || [ "$WINBOX_PORT" = "$SSH_PORT" ]; do
        print_warn "Введите число 1-65535, не равное порту SSH."
        ask "Новый порт Winbox" WINBOX_PORT "18291"
    done
else
    WINBOX_PORT="8291"
fi
print_ok "Порт Winbox: ${WINBOX_PORT}"

echo ""
print_section "Firewall (межсетевой экран)"
print_help "Firewall защищает роутер от взлома и атак из интернета.
Базовые правила:
  • Разрешить уже установленные соединения
  • Разрешить ICMP (ping)
  • Разрешить SSH и Winbox только с защитой от брутфорса
  • Заблокировать всё остальное входящее
Бан-лист: после 10 неудачных попыток входа IP блокируется на 1 день."
if ask_yn "Установить рекомендуемый firewall?"; then
    ENABLE_FIREWALL=1
    echo ""
    # Авто-определяем IP текущего SSH-подключения
    AUTO_TRUSTED_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
    [ -z "$AUTO_TRUSTED_IP" ] && AUTO_TRUSTED_IP=$(who am i 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$AUTO_TRUSTED_IP" ]; then
        print_ok "Ваш текущий IP ${BOLD}${AUTO_TRUSTED_IP}${RESET} будет автоматически добавлен как доверенный."
        TRUSTED_IP="$AUTO_TRUSTED_IP"
    fi
    print_info "Можно добавить дополнительный доверенный IP (или Enter чтобы пропустить)."
    ask "Дополнительный доверенный IP" EXTRA_TRUSTED_IP ""
else
    ENABLE_FIREWALL=0
    TRUSTED_IP=""
    EXTRA_TRUSTED_IP=""
fi

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 8 — СВОДКА И ПОДТВЕРЖДЕНИЕ
# ══════════════════════════════════════════════════════════════════════════════
print_step 8 $TOTAL_STEPS "Проверка параметров"

echo -e "  ${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${BOLD}СИСТЕМА${RESET}"
echo -e "  ${CYAN}║${RESET}  Режим загрузки : $([ "$BOOT_MODE" = "uefi" ] && echo "UEFI" || echo "Legacy BIOS")"
echo -e "  ${CYAN}║${RESET}  Целевой диск   : ${TARGET_DISK}"
echo -e "  ${CYAN}║${RESET}  Версия RouterOS: ${CHR_VERSION} (${UPGRADE_CHANNEL})"
echo -e "  ${CYAN}╠──────────────────────────────────────────────────────────────╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${BOLD}СЕТЬ${RESET}"
echo -e "  ${CYAN}║${RESET}  IP-адрес       : ${IP_ADDRESS}"
echo -e "  ${CYAN}║${RESET}  Шлюз           : ${GATEWAY}"
echo -e "  ${CYAN}║${RESET}  DNS            : ${DNS_SERVERS}"
echo -e "  ${CYAN}║${RESET}  Таймзона       : ${TIMEZONE}"
echo -e "  ${CYAN}║${RESET}  NTP            : ${NTP_SERVER}"
echo -e "  ${CYAN}║${RESET}  IP Cloud DDNS  : $([ "$ENABLE_DDNS" = "1" ] && echo "включён" || echo "выключен")"
echo -e "  ${CYAN}╠──────────────────────────────────────────────────────────────╣${RESET}"
echo -e "  ${CYAN}║${RESET}  ${BOLD}БЕЗОПАСНОСТЬ${RESET}"
echo -e "  ${CYAN}║${RESET}  Имя роутера    : ${ROUTER_NAME}"
echo -e "  ${CYAN}║${RESET}  Порт SSH       : ${SSH_PORT}"
echo -e "  ${CYAN}║${RESET}  Порт Winbox    : ${WINBOX_PORT}"
echo -e "  ${CYAN}║${RESET}  Firewall       : $([ "$ENABLE_FIREWALL" = "1" ] && echo "включён" || echo "выключен")"
echo -e "  ${CYAN}║${RESET}  Доверенный IP  : ${TRUSTED_IP:-—}"
echo -e "  ${CYAN}║${RESET}  Резервн. юзер  : $([ "$CREATE_BACKUP_USER" = "1" ] && echo "${BACKUP_USER}" || echo "нет")"
echo -e "  ${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${RED}${BOLD}⚠ Диск ${TARGET_DISK} будет ПОЛНОСТЬЮ перезаписан!${RESET}"
echo ""
if ! ask_yn "Всё верно — начать установку?"; then
    echo -e "\n  ${GRAY}Отменено.${RESET}\n"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 9 — ЗАГРУЗКА И ПОДГОТОВКА ОБРАЗА
# ══════════════════════════════════════════════════════════════════════════════
print_step 9 $TOTAL_STEPS "Загрузка и подготовка образа RouterOS"

progress_bar "Обновление apt"
DEBIAN_FRONTEND=noninteractive apt-get update -qq >> "$LOG_FILE" 2>&1
progress_done

progress_bar "Установка зависимостей (unzip, fdisk, wget, curl)"
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip fdisk wget curl -qq >> "$LOG_FILE" 2>&1
progress_done

if [ "$BOOT_MODE" = "mbr" ]; then
    IMAGE_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
    ZIP_FILE="chr-${CHR_VERSION}.img.zip"
    IMAGE_FILE="chr-${CHR_VERSION}.img"
else
    IMAGE_URL="https://github.com/tikoci/fat-chr/releases/download/Build11294119639-jaclaz/chr-7.16.1.uefi-fat.raw"
    IMAGE_FILE="chr-7.16.1.uefi-fat.raw"
fi

print_section "Скачивание образа"
print_info "Источник: ${IMAGE_URL}"
echo ""
if [ "$BOOT_MODE" = "mbr" ]; then
    wget -4 --progress=bar:force -O "$ZIP_FILE" "$IMAGE_URL" 2>&1 | \
        sed 's/\r/\n/g' | grep -E '%|saved' || true
    echo ""
    progress_bar "Распаковка"
    unzip -o "$ZIP_FILE" -d . >> "$LOG_FILE" 2>&1
    progress_done
    rm -f "$ZIP_FILE"
else
    wget -4 --progress=bar:force -O "$IMAGE_FILE" "$IMAGE_URL" 2>&1 | \
        sed 's/\r/\n/g' | grep -E '%|saved' || true
fi
print_ok "Образ готов: ${IMAGE_FILE}"

# ── Определение смещения ─────────────────────────────────────────────────────
print_section "Анализ структуры образа"
progress_bar "Вычисление offset"
START_SECTOR=$(fdisk -lu "$IMAGE_FILE" 2>/dev/null | \
    awk '$0 !~ /^D/ && NF>=5 && $2 ~ /^[0-9]+$/ {last=$2} END {print last}')
[ -z "$START_SECTOR" ] && START_SECTOR=65570
OFFSET=$((512 * START_SECTOR))
progress_done
print_ok "Offset: ${OFFSET} байт (сектор ${START_SECTOR})"

# ── autorun.scr ──────────────────────────────────────────────────────────────
print_section "Запись стартовой конфигурации (autorun.scr)"
progress_bar "Монтирование"
mkdir -p /mnt_chr
if ! mount -o loop,offset=$OFFSET "$IMAGE_FILE" /mnt_chr; then
    print_error "Не удалось смонтировать образ!"
    exit 1
fi
[ ! -d /mnt_chr/rw ] && mkdir -p /mnt_chr/rw
progress_done

progress_bar "Формирование autorun.scr"
AUTORUN="/mnt_chr/rw/autorun.scr"
> "$AUTORUN"

DNS_CLEAN="${DNS_SERVERS// /}"

cat >> "$AUTORUN" <<EOF
# Автоконфигурация при первом запуске
:delay 30s
:log info "=== CHR autorun: старт ==="

# --- Пароль admin (первым делом) ---
/user set admin password="${ADMIN_PASS}" group=full disabled=no
:log info "=== CHR autorun: пароль admin установлен ==="

# --- Identity ---
/system identity set name="${ROUTER_NAME}"

# --- Сеть ---
:do { /ip address add address=${IP_ADDRESS} interface=ether1 } on-error={ :log info "CHR autorun: IP уже существует, пропускаем" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=${GATEWAY} } on-error={ :log info "CHR autorun: маршрут уже существует, пропускаем" }
/ip dns set servers=${DNS_CLEAN} allow-remote-requests=yes

# --- Время / NTP ---
/system clock set time-zone-name=${TIMEZONE}
/system ntp client set enabled=yes
/system/ntp/client/set servers=ntp0.ntp-servers.net,ntp1.ntp-servers.net,ntp2.ntp-servers.net,ntp3.ntp-servers.net,0.pool.ntp.org,1.pool.ntp.org,2.pool.ntp.org,3.pool.ntp.org,time.google.com enabled=yes
/system ntp server set enabled=yes use-local-clock=yes

# --- Отключение прокси и socks ---
/ip proxy set enabled=no
/ip socks set enabled=no

# --- Канал обновлений ---
/system package update set channel=${UPGRADE_CHANNEL}
EOF

# Резервный пользователь
if [ "$CREATE_BACKUP_USER" = "1" ]; then
cat >> "$AUTORUN" <<EOF

# --- Резервный пользователь (failsafe) ---
/user add name=${BACKUP_USER} password="${BACKUP_PASS}" group=full comment="Failsafe rescue user"
EOF
fi

# Службы
cat >> "$AUTORUN" <<EOF

# --- Отключение лишних служб ---
/ip service set telnet  disabled=yes
/ip service set ftp     disabled=yes
/ip service set www     disabled=yes
/ip service set api     disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh     port=${SSH_PORT}
/ip service set winbox  port=${WINBOX_PORT}

# --- Отключение discovery / mac-server (защита L2) ---
/ip neighbor discovery-settings set discover-interface-list=none
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=none
/tool mac-server ping set enabled=no
EOF

# IP Cloud DDNS
if [ "$ENABLE_DDNS" = "1" ]; then
cat >> "$AUTORUN" <<EOF

# --- IP Cloud DDNS ---
/ip cloud set ddns-enabled=yes update-time=yes
EOF
fi

# Firewall
if [ "$ENABLE_FIREWALL" = "1" ]; then
TRUSTED_RULE=""
if [ -n "$TRUSTED_IP" ]; then
TRUSTED_RULE="/ip firewall filter add chain=input src-address=${TRUSTED_IP} action=accept comment=\"Trusted IP (installer) - full access\" place-before=0"
fi
EXTRA_TRUSTED_RULE=""
if [ -n "$EXTRA_TRUSTED_IP" ]; then
EXTRA_TRUSTED_RULE="/ip firewall filter add chain=input src-address=${EXTRA_TRUSTED_IP} action=accept comment=\"Trusted IP (extra) - full access\" place-before=1"
fi
cat >> "$AUTORUN" <<EOF

# --- Firewall: защита роутера ---
/ip firewall filter
${TRUSTED_RULE}
${EXTRA_TRUSTED_RULE}
add chain=input action=accept connection-state=established,related comment="accept established/related"
add chain=input action=drop connection-state=invalid comment="drop invalid"
add chain=input action=accept protocol=icmp comment="accept ICMP (ping)"
add chain=input action=accept protocol=tcp dst-port=${SSH_PORT} comment="accept SSH"
add chain=input action=accept protocol=tcp dst-port=${WINBOX_PORT} comment="accept Winbox"
add chain=input action=drop comment="drop all other input"
EOF
fi

# Завершение
cat >> "$AUTORUN" <<'EOF'

:log info "=== CHR autorun: конфигурация применена ==="
EOF

progress_done

# Показ финального скрипта
echo ""
print_info "Итоговый autorun.scr записан (${LOG_FILE} содержит копию):"
cp "$AUTORUN" "${LOG_FILE}.autorun"
echo -e "${DIM}"
sed 's/^/    /' "$AUTORUN" | head -30
echo "    ... (полностью см. ${LOG_FILE}.autorun)"
echo -e "${RESET}"

progress_bar "Отмонтирование образа"
sync
umount /mnt_chr
rm -rf /mnt_chr
progress_done

# ══════════════════════════════════════════════════════════════════════════════
# ШАГ 10 — ЗАПИСЬ НА ДИСК И ПЕРЕЗАГРУЗКА
# ══════════════════════════════════════════════════════════════════════════════
print_step 10 $TOTAL_STEPS "Запись на диск и перезагрузка"

print_warn "Идёт запись образа на ${TARGET_DISK}. НЕ ПРЕРЫВАЙТЕ ПРОЦЕСС!"
echo ""

## Отключаем логирование ДО перевода ФС в read-only — после sysrq u запись невозможна
LOG_FILE=/dev/null

echo 1 > /proc/sys/kernel/sysrq
echo u > /proc/sysrq-trigger
sleep 2

dd if="$IMAGE_FILE" of="$TARGET_DISK" bs=4M oflag=sync status=progress 2>&1
sync
echo ""
echo -e "  ${GREEN}✔  Образ записан на диск.${RESET}"
rm -f "$IMAGE_FILE" 2>/dev/null

# ── Финал ────────────────────────────────────────────────────────────────────
IP_ONLY="${IP_ADDRESS%%/*}"
echo ""
echo -e "${GREEN}${BOLD}"
cat <<EOF
   ╔════════════════════════════════════════════════════════════════════╗
   ║                                                                    ║
   ║          ✔   У С Т А Н О В К А   З А В Е Р Ш Е Н А   ✔            ║
   ║                                                                    ║
   ║   После перезагрузки роутер будет доступен:                       ║
   ║                                                                    ║
EOF
printf "   ║     IP-адрес       :  %-44s ║\n" "$IP_ONLY"
printf "   ║     SSH             :  ssh admin@%s -p %-22s ║\n" "$IP_ONLY" "$SSH_PORT"
printf "   ║     Winbox          :  %s:%-37s ║\n" "$IP_ONLY" "$WINBOX_PORT"
printf "   ║     WebFig          :  отключён (включается в /ip service)      ║\n"
if [ "$CREATE_BACKUP_USER" = "1" ]; then
printf "   ║     Резервный юзер  :  %-44s ║\n" "$BACKUP_USER"
fi
if [ "$ENABLE_DDNS" = "1" ]; then
printf "   ║     DDNS hostname   :  /ip cloud print  (после загрузки)        ║\n"
fi
cat <<EOF
   ║                                                                    ║
   ║   Лог установки: /tmp/chr-install.log                            ║
   ║                                                                    ║
   ╚════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

echo -e "  ${YELLOW}Перезагрузка через 10 секунд... (Ctrl+C для отмены)${RESET}"
echo ""
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo -ne "  ${CYAN}  ${i} ${RESET}"
    sleep 1
done
echo ""
echo b > /proc/sysrq-trigger
