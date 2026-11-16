# Runbook — развёртывание Hermes Agent на VPS

Пошаговый сценарий, покрывающий раздел задания **«Ход работы»** (п. 1–18).
Выполняется на отдельном VPS Ubuntu 22.04+, без личных данных и чужих ключей.
Команды даны для пользователя `ubuntu`; подставьте свой логин/IP.

> ⚠️ Безопасность до первого запуска: отдельный VPS, непривилегированный
> пользователь (не root), в allowlist шлюза только свой id, ключи вне репозитория,
> лимит расходов у LLM-провайдера установлен ДО запуска планировщика.

---

## 0. Параметры стенда (зафиксировать в отчёте)

| Параметр        | Значение (заполнить фактом)                       |
|-----------------|---------------------------------------------------|
| Провайдер VPS   | напр. Selectel / Timeweb / aeza                   |
| Тариф           | напр. 1 vCPU / 1 ГБ RAM / 10 ГБ NVMe              |
| Регион          | напр. Москва (ru-1)                               |
| ОС              | Ubuntu 22.04 LTS                                   |
| Стоимость       | напр. ~200 ₽/мес                                   |
| IP / домен      | напр. 203.0.113.10                                 |

---

## 1. Арендовать VPS
Заказать Linux VPS (Ubuntu 22.04+, ≥1 vCPU / 1 ГБ RAM). Для облачной LLM этого
достаточно; локальной модели здесь нет, GPU не нужен. Зафиксировать параметры (см. §0).

## 2. Базовая настройка сервера (hardening)
Зайти по SSH первый раз, затем:
```bash
# 2.1 Создать непривилегированного пользователя (если вход был под root)
adduser hermesadmin && usermod -aG sudo hermesadmin

# 2.2 Скопировать свой публичный ключ этому пользователю
#     (с локальной машины):  ssh-copy-id hermesadmin@<IP>

# 2.3 Обновить пакеты
sudo apt update && sudo apt -y upgrade

# 2.4 Отключить вход по паролю и под root
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# 2.5 Firewall: пускаем только SSH (порты агента наружу НЕ открываем — §8)
sudo ufw allow OpenSSH && sudo ufw --force enable && sudo ufw status
```
Зафиксировать выполненные шаги для отчёта (раздел «Ход работы»).

## 3. Установить Docker и Docker Compose
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER" && newgrp docker   # запуск docker без sudo
docker run --rm hello-world                          # контрольная проверка
docker compose version
```

## 4. Выбрать LLM-провайдера и получить ключ (OpenRouter)
- Зарегистрироваться на https://openrouter.ai, создать ключ (`sk-or-v1-...`).
- Модель: `meta-llama/llama-3.3-70b-instruct:free` — контекст **131k ≥ 64k** ✔,
  function calling есть. Fallback: `meta-llama/llama-4-maverick:free` (1M контекст).
- Проверить соответствие требованию контекста (≥64k) — выполнено.

## 5. Установить лимит расходов у провайдера (ДО запуска!)
- OpenRouter → Settings → Limits: задать дневной лимит кредитов (напр. $1/день) и,
  при наличии, лимит запросов. Бесплатные `:free`-модели ограничены ~20 запросов/мин.
- Зафиксировать установленные значения + скриншот панели (нужен для P1).

## 6. Подготовить Telegram-шлюз
- `@BotFather` → `/newbot` → получить **TELEGRAM_BOT_TOKEN**.
- Узнать свой числовой **user id** у `@userinfobot` / `@Getmyid_Work_Bot`.

## 7. Запустить мастер настройки в контейнере
Каталог конфигурации на хосте — `~/.hermes` (монтируется как `/opt/data`):
```bash
mkdir -p ~/.hermes
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent:latest setup
```
Мастер спросит провайдера (OpenRouter), API-ключ, модель, токен и id Telegram.
Убедиться, что конфиг записан именно в `~/.hermes` (тот каталог, что смонтируется §9).

Затем положить рядом подготовленные файлы из этого репозитория:
```bash
cp deploy/.env.example ~/.hermes/.env   # заполнить реальными ключами!
chmod 600 ~/.hermes/.env
cp deploy/config.yaml  ~/.hermes/config.yaml
mkdir -p ~/.hermes/memories ~/.hermes/skills ~/.hermes/cron
cp hermes/memories/*.md            ~/.hermes/memories/
cp -r hermes/skills/arxiv-digest   ~/.hermes/skills/
cp hermes/cron/arxiv-digest.yaml   ~/.hermes/cron/
```

## 8. Описать compose.yaml
Используем `deploy/compose.yaml` (с комментариями). Ключевое:
образ `nousresearch/hermes-agent:latest`, `container_name: hermes`,
`restart: unless-stopped`, `command: gateway run`, монтирование
`~/.hermes:/opt/data`. Порты публикуются только на `127.0.0.1` (наружу — через
SSH-туннель, не firewall). Проверить, что точка монтирования = `/opt/data`.

## 9. Запустить контейнер в фоне и посмотреть логи
```bash
export HERMES_UID="$(id -u)" HERMES_GID="$(id -g)"
cp deploy/compose.yaml ~/compose.yaml && cd ~
docker compose up -d
docker compose logs -f
```
**Контрольный признак старта:** в логах ненулевое число навыков («NN total
bundled») и отсутствие `No messaging platforms enabled`. Если «0 bundled» —
проверить путь монтирования (`/opt/data`).

## 10. Проверить связку
Написать боту в Telegram, получить ответ. **Зафиксировать время отклика** и скриншот диалога.

## 11. Ограничить доступ
В `~/.hermes/.env` → `TELEGRAM_ALLOWED_USERS=<свой id>` (только свой).
`GATEWAY_ALLOW_ALL_USERS` — НЕ ставить. С тестового аккаунта убедиться, что
бот **не отвечает** постороннему → скриншот отказа (P1, доказательство изоляции).

## 12. Настроить память
`~/.hermes/memories/USER.md` и `MEMORY.md` уже заполнены (см. `hermes/memories/`).
Проверить, что агент опирается на них: задать вопрос, ответ на который возможен
только с их учётом (напр. «в какую ветку ты пушишь изменения сайта?» → ожидаем
«в ветку `agent/*` через PR, не в main» из MEMORY.md).

## 13. Подключить и проверить инструменты
Проверить по очереди: веб-поиск, загрузка страницы, запись файла, запуск
разрешённой команды (`git`, `python3`), постановка cron-задачи. Зафиксировать.

## 14. Создать первый навык
Навык `arxiv-digest` (P2) уже в `~/.hermes/skills/`. Убедиться, что он
подхватился (виден в списке навыков / `hermes doctor`) и срабатывает по команде
«дайджест arxiv».

## 15. Поставить задачу по расписанию (cron)
Через `~/.hermes/cron/arxiv-digest.yaml` или командой в чате:
«Каждый день в 9 утра присылай дайджест arxiv по RUL».
Дождаться автономного срабатывания (можно временно поставить `*/10 * * * *` для
проверки), зафиксировать результат и журнал.

## 16. (P1) Доказать автономность
```bash
sudo reboot           # после ребута агент поднимается сам (restart: unless-stopped)
# через ~1 мин:
docker compose ps     # hermes снова Up
```
Убедиться, что cron-задача срабатывает при **закрытом** Telegram на стороне
пользователя (бот присылает дайджест сам). Зафиксировать.

## 17. Настроить сохранение логов (ротация)
Docker-логи уже ограничены в `compose.yaml` (`max-size 10m`, `max-file 5`).
Логи навыков — `~/.hermes/logs/`. Для ротации файловых логов:
```bash
sudo tee /etc/logrotate.d/hermes >/dev/null <<'EOF'
/home/*/.hermes/logs/**/*.log {
  weekly
  rotate 8
  compress
  missingok
  notifempty
}
EOF
```

## 18. Отладка
Фиксировать возникшие ошибки, гипотезы, проверки, решения → раздел «Отладка»
в `REPORT.md` (минимум 3 реальных ошибки).

---

## Откат / удаление (для P3 и чистоты стенда)
```bash
docker compose down            # остановить агента
docker compose down -v         # + удалить тома (осторожно)
# откат изменения, внесённого агентом в сайт:
git -C <repo> revert <commit>  # или закрыть PR без merge
```

## Публикация портов наружу (только при необходимости, безопасно)
Дашборд слушает `127.0.0.1:9119`. Смотреть с локальной машины через SSH-туннель,
НЕ открывая порт в firewall:
```bash
ssh -L 9119:127.0.0.1:9119 hermesadmin@<IP>   # затем http://localhost:9119
```
