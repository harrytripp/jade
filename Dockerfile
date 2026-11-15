# syntax=docker/dockerfile:1

# Keep in step with the go directive in go.mod.
ARG GO_VERSION=1.27.1
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build
WORKDIR /src

# Download modules in their own layer, cached across builds.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x

# Declared after the download step so that layer is shared across architectures.
ARG TARGETARCH

# modernc.org/sqlite is pure Go, so the binary builds with CGO_ENABLED=0 and
# needs no libc at runtime.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=bind,target=. \
    CGO_ENABLED=0 GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /bin/app .

# Data directory for the database volume. scratch has no shell, so it's made here.
RUN mkdir -p /out/app/store

################################################################################
FROM scratch AS final

# Owned by the unprivileged runtime user. Docker copies this ownership into a
# new, empty named volume mounted here.
COPY --from=build --chown=65532:65532 /out/app /app
COPY --from=build /bin/app /bin/app

# The config is mounted at /bin/config.json, which the default CONFIG_PATH
# (./config.json) points to from here.
WORKDIR /bin
USER 65532:65532

# Read-only report API (http_listen in the config).
EXPOSE 8090

ENTRYPOINT [ "/bin/app" ]