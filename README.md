# Интеграция API PT AI Enterprise Server для CI/CD

Этот репозиторий содержит Bash-скрипт для облегчения интеграции с API PT AI Enterprise Server в CI/CD пайплайнах (например, GitLab CI).

## Возможности

- **Аутентификация**: Использование `AISA_HOST` и `AISA_TOKEN` для прямой аутентификации.
- **Поддержка самоподписанных сертификатов**: Опциональная поддержка через `PT_AI_INSECURE_SSL`.
- **Управление ветками**: Автоматическая установка ветки по умолчанию (working branch).
- **Парсинг логов**: Парсинг логов выполнения (например, от `ptai-cli-plugin`) для автоматического определения ветки для установки.

## Требования

- `bash`
- `curl`
- `jq`

## Использование

### 1. Настройка

Установите следующие переменные окружения в настройках CI/CD или в скрипте:

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `AISA_HOST` | Базовый URL сервера PT AI Enterprise (например, `https://pt-ai.example.com`) | Обязательно |
| `AISA_TOKEN` | API токен для PT AI | Обязательно |
| `PT_AI_API_VERSION` | Номер версии API (например, `2`). Оставьте пустым, если версия не указана в пути URL. | `2` (или пусто, если изменено) |
| `PT_AI_INSECURE_SSL` | Установите в `true`, чтобы пропустить проверку SSL (например, для самоподписанных сертификатов) | `false` |

### 2. Подключение скрипта

Подключите скрипт в вашем пайплайне, чтобы функции стали доступны:

```bash
source ./pt_ai_api.sh
```

### 3. Автоматизированный рабочий процесс (с использованием логов)

Если вы запускаете `ptai-cli-plugin` (инструмент AISA) и сохраняете его логи, вы можете использовать `pt_ai_automate_process` для автоматической установки рабочей ветки на основе Branch ID, найденного в логах.

**Синтаксис:**
```bash
pt_ai_automate_process <ФАЙЛ_ЛОГА>
```

**Пример:**
```bash
# Захват логов от инструмента
java -jar ptai-cli-plugin.jar ... | tee scan.log

# Автоматическая установка рабочей ветки
pt_ai_automate_process "scan.log"
```

Эта функция выполнит следующие действия:
1.  Распарсит Branch ID (ID ветки) напрямую из `scan.log`.
2.  Установит эту ветку как "рабочую" (working branch).

### 4. Ручное использование

Вы также можете использовать базовые функции напрямую:

#### Установка рабочей ветки
```bash
# pt_ai_set_working_branch <BRANCH_ID>
pt_ai_set_working_branch "branch-uuid"
```

#### Выполнение запросов к API
Используйте `pt_ai_api_request` для выполнения аутентифицированных вызовов.

**Синтаксис:**
```bash
pt_ai_api_request <METHOD> <ENDPOINT> [CURL_OPTIONS...]
```

**Примеры:**

```bash
# GET запрос
response=$(pt_ai_api_request GET "/projects")
echo "$response"

# POST запрос с данными
pt_ai_api_request POST "/scans" -d '{"projectId": "123"}'
```

## Пример для GitLab CI

```yaml
security_job:
  stage: security
  script:
    - |
      set -o pipefail
      # Запуск сканирования и захват логов
      java -jar /opt/ptai/bin/ptai-cli-plugin.jar ... | tee .report/ptai-scan.log

      source ./pt_ai_api.sh
      # Автоматическая обработка результатов
      pt_ai_automate_process ".report/ptai-scan.log"
  artifacts:
    paths:
      - PlainReport.html
      - Sarif.json
```
