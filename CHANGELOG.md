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
