FROM debian:trixie-slim

ARG TARGETARCH

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libuv1 libluajit-5.1-2 libcurl4 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the correct per-arch staging directory
COPY staging/${TARGETARCH}/ /app/

RUN chmod +x /app/bin/lunet /app/run.sh 2>/dev/null || true

ENV LUA_CPATH="/app/lib/?.so;;"

EXPOSE 8080

ENTRYPOINT ["/app/bin/lunet"]
CMD ["--dangerously-skip-loopback-restriction", "/app/app/main.lua"]
