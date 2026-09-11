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
