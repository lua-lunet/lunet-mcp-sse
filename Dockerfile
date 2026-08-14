FROM debian:trixie-slim

ARG TARGETARCH

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libuv1 libluajit-5.1-2 libcurl4 zlib1g ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY staging/${TARGETARCH}/ /app/
RUN chmod +x /app/lunet-run /app/run.sh 2>/dev/null || true

WORKDIR /app

EXPOSE 8080

ENTRYPOINT ["/app/lunet-run"]
CMD ["--dangerously-skip-loopback-restriction", "app/main.lua"]
