# Use latest stable channel SDK.
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart build cli --target bin/server.dart -o output

# Build minimal serving image from AOT-compiled `/server`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM debian:stable-slim

# sqlite3 работает через FFI и требует системную библиотеку libsqlite3.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
    && ln -s /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so \
    && rm -rf /var/lib/apt/lists/*


COPY --from=build /app/output/bundle/ /app/
# Нужен для фолбэка версии: если APP_VERSION не задана (dev/локальная сборка),
# версия читается из pubspec.yaml.
COPY --from=build /app/pubspec.yaml /app/pubspec.yaml

WORKDIR /app

# Версия и коммит сборки: передаются через --build-arg (из тега git-релиза).
ARG VERSION=local
ENV APP_VERSION=$VERSION
ARG COMMIT=unknown
ENV APP_COMMIT=$COMMIT

# Директория для базы данных (монтируется как volume).
ENV DB_PATH=/data/ai_server.db
RUN mkdir -p /data

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]