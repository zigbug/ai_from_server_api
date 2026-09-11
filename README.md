# AI Server API

Backend на Dart (shelf) для Flutter-приложений. Работает целиком через
**Hugging Face Inference API** (без OpenRouter): принимает промт из приложения
и возвращает текстовый ответ или сгенерированное/отредактированное изображение.

## Возможности

- **Текстовые модели** — Hugging Face Inference API (text-generation).
  Список текстовых моделей подтягивается с Hugging Face Hub автоматически
  (топ по загрузкам, кэш на час, fallback при недоступности Hub)
- **Генерация изображений** — Stable Diffusion / FLUX через Hugging Face
- **Сессии диалогов** — с системным промтом (роли/игры) и историей на SQLite
- **Умный контекст** — скользящее окно (по умолчанию 20 сообщений) +
  автоматическое резюмирование старой истории через ту же модель
- **Список моделей** — эндпоинт `/models` подтягивает с Hugging Face Hub модели
  по категориям `text`/`image`/`edit` с флагом `free` (бесплатность модели)
- **Health + версия** — `/health` для мониторинга и проверки версии деплоя

## Запуск локально

```bash
dart pub get
dart run bin/server.dart
```

Переменные окружения:

| Переменная | Назначение | По умолчанию |
|---|---|---|
| `PORT` | Порт сервера | `8080` |
| `DB_PATH` | Путь к файлу SQLite | `data/ai_server.db` |
| `HF_TOKEN` | Токен Hugging Face | — |
| `CONTEXT_WINDOW` | Окно сообщений, передаваемых модели | `20` |
| `SUMMARY_THRESHOLD` | Порог сообщений для резюмирования | `40` |
| `IMAGE_MODEL` | Модель изображений по умолчанию | `stabilityai/stable-diffusion-xl-base-1.0` |
| `IMAGE_EDIT_MODEL` | Модель редактирования изображений по умолчанию | `black-forest-labs/FLUX.1-Kontext-dev` |
| `APP_VERSION` | Версия приложения (для /health) | `dev` |

## Как пользоваться беком

Бэкенд — «тонкий прокси» над Hugging Face: приложение не хранит историю и не
знает моделей. Все контексты и маршрутизация — на сервере. Типовой сценарий:

1. **Получить модели** — `GET /models` (см. ниже). Берите любой `id` из нужной
   категории: `text`, `image`, `edit`. Флаг `free: true/false` показывает,
   бесплатна ли модель.
2. **Создать сессию** — `POST /sessions` с `{"name", "model", "system_prompt"}`.
   В ответе — `id` сессии (сохраните его, он нужен для всех следующих шагов).
3. **Отправить сообщение** — `POST /sessions/<id>/messages` с `{"message": "..."}`.
   История и контекст ведутся на сервере автоматически.
4. **Сгенерировать картинку** — `POST /images` с `{"prompt": "..."}`.
   **Отредактировать** — `POST /images/edit` (исходная картинка в base64).

Весь контекст (`CONTEXT_WINDOW` последних сообщений + авто-резюме) собирается
сервером сам — клиент передаёт только текст нового сообщения.

### Минимальный пример (curl)

```bash
# 1) Список моделей и категорий (текст / картинки / редактирование)
curl https://aiapi.905911.ru:8445/models

# 2) Создаём сессию и запоминаем id
curl -X POST https://aiapi.905911.ru:8445/sessions \
  -H "Content-Type: application/json" \
  -d '{"name":"Демо","model":"Qwen/Qwen2.5-7B-Instruct","system_prompt":"Ты — помощник."}'

# 3) Отправляем сообщение (подставьте session_id из шага 2)
curl -X POST https://aiapi.905911.ru:8445/sessions/<session_id>/messages \
  -H "Content-Type: application/json" \
  -d '{"message":"Привет! Расскажи анекдот"}'

# 4) Генерируем картинку
curl -X POST https://aiapi.905911.ru:8445/images \
  -H "Content-Type: application/json" \
  -d '{"prompt":"кот в скафандре","model":"stabilityai/stable-diffusion-xl-base-1.0"}'
```

> Весь API защищён только HTTPS-портом `8445` на проде; локально — `8080`.

Единый источник правды по API — `docs/openapi.yaml` и коллекции для Insomnia /
Postman (`docs/*_hf.*`). Полный референс всех эндпоинтов — ниже.

## API

### `GET /health`
Статус, версия и количество сессий.

### `GET /models`
Модели подтягиваются напрямую с Hugging Face Hub (кэш 1 час). Ответ — объект
с категориями по видам задач:

```json
{
  "text": [
    {"id": "Qwen/Qwen2.5-7B-Instruct", "name": "Qwen2.5 7B Instruct", "kind": "text", "provider": "huggingface", "free": true},
    {"id": "meta-llama/Llama-3.1-8B-Instruct", "name": "Llama 3.1 8B Instruct", "kind": "text", "provider": "huggingface", "free": false}
  ],
  "image": [
    {"id": "stabilityai/stable-diffusion-xl-base-1.0", "name": "Stable Diffusion Xl Base 1.0", "kind": "image", "provider": "huggingface", "free": true}
  ],
  "edit": [
    {"id": "black-forest-labs/FLUX.1-Kontext-dev", "name": "FLUX.1 Kontext Dev", "kind": "edit", "provider": "huggingface", "free": false}
  ]
}
```

Категории (соответствуют `pipeline_tag` на HF):
- `text` — модели для чата (`text-generation`);
- `image` — генерация картинок с нуля (`text-to-image`);
- `edit` — редактирование загруженных картинок (`image-to-image`).

Поля модели:
- `id` — подставляется в `model` при создании сессии / генерации;
- `name` — человекочитаемое название для меню;
- `kind` — категория (`text` / `image` / `edit`);
- `provider` — всегда `huggingface`;
- `free` — бесплатна ли модель: `false`, если она `gated` на HF
  (требует согласия на доступ / PRO). `true` — использование открытое
  (в рамках лимитов free-тира HF Inference).

`GET /models?refresh=1` принудительно сбрасывает кэш и заново запрашивает Hub.
При недоступности Hub используется статический запасной список
(`HuggingFaceH4/zephyr-7b-beta`, `mistralai/Mistral-7B-Instruct-v0.3`,
`Qwen/Qwen2.5-7B-Instruct` и др.).

Используйте для меню настроек в приложении.

### `POST /sessions`
Создать новую сессию диалога.
```json
{
  "name": "Игра 'Мастер подземелий'",
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "system_prompt": "Ты — мастер подземелий..."
}
```
Ответ: `201` + данные сессии (включая `id`).

### `GET /sessions`
Список всех сессий.

### `GET /sessions/<id>`
Данные одной сессии.

### `PATCH /sessions/<id>`
Обновить `name`, `model`, `system_prompt`.

### `DELETE /sessions/<id>`
Удалить сессию и её историю.

### `GET /sessions/<id>/history`
История сообщений сессии + текущее резюме:
```json
{
  "session_id": "...",
  "summary": "...",
  "messages": [{"role": "user", "content": "...", "created_at": "..."}]
}
```

### `POST /sessions/<id>/messages`
Отправить сообщение в сессию и получить ответ модели.
```json
{"message": "Привет! Расскажи анекдот"}
```
Ответ:
```json
{"response": "Отвечает модель..."}
```
История хранится на сервере автоматически; клиент не передаёт контекст.

### `POST /images`
Сгенерировать изображение по промту.
```json
{"prompt": "кот в скафандре", "model": "black-forest-labs/FLUX.1-schnell"}
```
Ответ (изображение в base64):
```json
{
  "image": "<base64>",
  "mime_type": "image/png",
  "prompt": "...",
  "model": "..."
}
```

### `POST /images/edit`
Редактирование загруженной картинки (image-to-image): приложение отправляет
картинку (base64) + инструкцию-промт, получает изменённую картинку.
```json
{
  "prompt": "сделай это фото в стиле киберпанк",
  "image": "<base64 исходной картинки>",
  "model": "black-forest-labs/FLUX.1-Kontext-dev",
  "negative_prompt": "размытость, шум",
  "guidance_scale": 7.5,
  "num_inference_steps": 30,
  "width": 512,
  "height": 512
}
```
Обязательные поля: `prompt`, `image`. Остальные — опциональные параметры
генерации. Ответ — как у `POST /images` (изображение в base64).

## Контекст диалога

Клиент не передаёт историю. Сервер хранит сообщения в SQLite и передаёт
модели только последние `CONTEXT_WINDOW` сообщений. Когда сообщений становится
больше `SUMMARY_THRESHOLD`, старая часть истории сжимается в короткое резюме
(через ту же модель), которое добавляется в системный промт. Это позволяет
вести длинные диалоги/игры без роста запроса и потери начала контекста.

## Деплой

### Структура

- `Dockerfile` — AOT-компиляция + минимальный Debian-образ с `libsqlite3`
- `docker-compose.yml` — сервис с volume для БД и пробросом ключей из `.env`
- `.github/workflows/deploy.yml` — GitHub Actions: деплой по тегу `v*`

### Сервер (один раз)

1. Установить Docker + Docker Compose.
2. Скопировать репозиторий в каталог приложения (рекомендуется `/opt/ai-server`).
3. Создать `.env` по образцу `.env.example` и заполнить ключи.
4. Проверить, что секреты в GitHub совпадают со значениями на сервере
   (`SERVER_HOST` = `aiapi.905911.ru`, etc).

### Публикация новой версии

1. Внести изменения в `main`.
2. Создать тег с номером версии:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
3. GitHub Actions автоматически выполнит: checkout → SSH на сервер →
   `docker compose build` (передаёт тег как `VERSION`) → `docker compose up -d`.
4. БД сохраняется в Docker volume — данные не теряются при обновлении.

### Необходимые секреты GitHub (Settings → Secrets and variables → Actions)

| Секрет | Значение |
|---|---|
| `SERVER_HOST` | IP/домен сервера (aiapi.905911.ru) |
| `SERVER_USER` | SSH-пользователь |
| `SERVER_SSH_KEY` | Приватный SSH-ключ |
| `SERVER_PORT` | SSH-порт (обычно 22) |
| `APP_DIR` | Каталог с `docker-compose.yml` на сервере |

## Тесты

```bash
dart test
```

Проверяют: health, список моделей, CRUD сессий, историю, 404.

## Документация API

- `docs/openapi.yaml` — спецификация OpenAPI 3.0 (можно открыть в Swagger UI /
  Redoc / импортировать в Insomnia как "Import from OpenAPI").
- `docs/insomnia_collection_hf.json` — готовая коллекция для Insomnia (File →
  Import → Import from File). Настроены переменные окружения: `baseUrl`,
  `sessionId`, модели. После создания сессии вставьте `session_id` в переменную
  `sessionId` в Insomnia, и остальные запросы сессии заработают. Работа целиком
  через Hugging Face (без OpenRouter): `modelText` по умолчанию
  `Qwen/Qwen2.5-7B-Instruct`, остальные модели подставляются из `GET /models`.
- `docs/postman_collection_hf.json` — та же коллекция для Postman (+ окружение
  `docs/postman_environment_production_hf.json`).

`baseUrl` во всех коллекциях: `https://aiapi.905911.ru:8445` (порт 8445
принимает только HTTPS).