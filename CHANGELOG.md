## 2.2.0

- **Генерация картинок через Pollinations**: добавлен `PollinationsImageProvider`
  (`image.pollinations.ai/prompt/`, без ключа, работает из РФ). Модель
  `pollinations/sana` добавлена первой в каталог image-моделей, по умолчанию
  `/images` генерирует через неё. Edit (image-to-image) Pollinations не
  поддерживает — остаётся на Hugging Face.
- **`/models` для картинок**: объединяет статический список (включая
  `pollinations/sana`) и динамический HF-каталог.

## 2.1.0

- **Groq для текстовых моделей**: добавлен `GroqProvider`
  (OpenAI-совместимый `api.groq.com/openai/v1`). Конфиг `GROQ_API_KEY`:
  если ключ не задан — Groq-модели скрываются, поведение не меняется.
- **Статический каталог Groq**: `openai/gpt-oss-20b`, `openai/gpt-oss-120b`,
  `qwen/qwen3-32b`, `groq/compound`, `groq/compound-mini` (провайдер `groq`).
  При наличии ключа список дополняется динамически списком моделей аккаунта.
- **Маршрутизация по провайдеру**: модель с `provider=groq` уходит в Groq,
  `huggingface` — в Hugging Face, остальное (включая `openrouter/free`) —
  в OpenRouter. Модели с дублирующимися ID (например, `openai/gpt-oss-20b`
  на HF Hub и Groq) гарантированно отправляются в Groq.

## 2.0.1

- **Фикс Inference API**: Hugging Face отключил старый хост
  `api-inference.huggingface.co`. Все запросы к моделям теперь идут на
  `https://router.huggingface.co/hf-inference/models/<model>`.

## 2.0.0

- **Полный уход от OpenRouter**: удалён `OpenRouterProvider`, конфиг
  `OPENROUTER_API_KEY` и все не-HF коллекции. Все запросы (чат, резюме,
  картинки, редактирование) идут только через Hugging Face Inference API.
- **Динамический каталог по категориям**: `/models` подтягивает модели
  напрямую с Hugging Face Hub для `text` (text-generation), `image`
  (text-to-image) и `edit` (image-to-image) с кэшем 1 час.
- **Флаг `free`**: каждая модель в `/models` помечается `free` (не gated на
  Hugging Face). `GET /models?refresh=1` сбрасывает кэш.
- **Валидация моделей** через динамический каталог: image/edit-модели нельзя
  использовать для текстового чата, и наоборот.

## 1.0.1

- **Динамический список HF-моделей**: `/models` дополняет статический список
  текстовых моделей топом `text-generation` моделей с Hugging Face Hub
  (кэш 1 час, статический fallback при недоступности Hub).
- **Маршрутизация без OpenRouter**: текстовые модели, выбранные из HF-списка,
  обрабатываются через Hugging Face Inference API.
- **HF-коллекции**: `docs/insomnia_collection_hf.json`,
  `docs/postman_collection_hf.json` и `docs/postman_environment_production_hf.json`
  для работы целиком через Hugging Face.
- **Исправлен `baseUrl`** в коллекциях: `https://aiapi.905911.ru:8445`
  (порт 8445 принимает только HTTPS).

## 1.0.0

- Initial version.
